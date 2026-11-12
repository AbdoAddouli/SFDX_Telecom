import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import startWizard from '@salesforce/apex/SubscriptionWizardController.start';
import saveWizard from '@salesforce/apex/SubscriptionWizardController.save';
import getAccountContext from '@salesforce/apex/SubscriptionWizardController.getAccountContext';
import getPlans from '@salesforce/apex/CatalogQueryService.getPlans';
import getDevices from '@salesforce/apex/CatalogQueryService.getDevices';
import getOptions from '@salesforce/apex/CatalogQueryService.getOptions';
import getPriceBreakdown from '@salesforce/apex/CatalogQueryService.getPriceBreakdown';
import filterByEligibility from '@salesforce/apex/CatalogQueryService.filterByEligibility';
import createQuote from '@salesforce/apex/SubscriptionWizardController.createQuote';
import saveContactDetails from '@salesforce/apex/SubscriptionWizardController.saveContactDetails';

const DEFAULT_COMMITMENT = 'NOCOMMIT';
const TODAY = localDate();

const COMMITMENT_OPTIONS = [
    { label: 'No commitment', value: 'NOCOMMIT' },
    { label: '12 months', value: 'COMMIT12' },
    { label: '24 months', value: 'COMMIT24' }
];

const OFFER_OPTIONS = [
    { label: 'Mobile', value: 'Mobile' },
    { label: 'Fibre & Landline', value: 'Fiber' }
];

export default class SubscriptionWizard extends NavigationMixin(LightningElement) {
    @api recordId;

    isLoading = false;
    errorMessage = '';
    sessionId;
    accountId;
    accountName = '';
    accountSegment = '';
    contactId = '';
    contactOptions = [];
    isAutosync = true;
    contactEmail = '';
    contactPhone = '';
    contactSaveMessage = '';
    contactSaveError = false;
    contactSaveTimer;
    contactSavePending = false;
    opportunityId;
    offerType = '';
    commitmentCode = DEFAULT_COMMITMENT;
    planProductId;
    deviceProductId;
    postalCode = '';
    effectiveDate = TODAY;
    currentStep = '1';
    plans = [];
    devices = [];
    planConfigs = [];
    deviceConfigs = [];
    pricing = [];
    pricingTotal = 0;
    quoteCreated = false;
    quoteResult;

    connectedCallback() {
        this.bootstrap();
    }

    disconnectedCallback() {
        if (this.contactSaveTimer) {
            clearTimeout(this.contactSaveTimer);
            this.contactSaveTimer = null;
        }
    }

    async bootstrap() {
        if (!this.recordId) {
            this.errorMessage =
                'Open this wizard from an Account record so the customer can be resolved.';
            return;
        }

        this.isLoading = true;
        try {
            const [context, state] = await Promise.all([
                getAccountContext({ accountId: this.recordId }),
                startWizard({
                    accountId: this.recordId,
                    contactId: null,
                    opportunityId: null,
                    sessionId: null
                })
            ]);

            this.accountId = context.accountId;
            this.accountName = context.accountName;
            this.accountSegment = context.segment || '';
            this.isAutosync = context.isAutosync !== false;
            this.contactOptions = (context.contacts || []).map((contact) => ({
                label: contact.name,
                value: contact.contactId,
                email: contact.email || '',
                phone: contact.phone || '',
                detail: contact.email || contact.phone || ''
            }));

            this.applyState(state);
            this.syncContactFields();
            if (this.offerType) {
                await this.loadPlans(false);
            }
            if (this.planProductId) {
                await this.loadPlanOptions();
            }
            if (Number(this.currentStep) >= 4) {
                await this.loadDevices(false);
            }
            if (this.deviceProductId) {
                await this.loadDeviceOptions();
            }
            if (Number(this.currentStep) >= 5) {
                await this.loadPricing();
            }
        } catch (error) {
            this.errorMessage = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    applyState(state) {
        this.sessionId = state.sessionId;
        this.accountId = state.accountId || this.recordId;
        this.contactId = state.contactId || '';
        this.opportunityId = state.opportunityId;
        this.offerType = state.offerType || '';
        this.planProductId = state.planProductId || null;
        this.deviceProductId = state.deviceProductId || null;
        this.commitmentCode = state.commitmentCode || DEFAULT_COMMITMENT;
        this.currentStep = String(state.step || 1);

        const extra = parseJson(state.stateJson);
        this.postalCode = extra.postalCode || '';
        this.effectiveDate = extra.effectiveDate || TODAY;

        if (state.quoteId) {
            this.quoteCreated = true;
            this.quoteResult = {
                quoteId: state.quoteId,
                quoteNumber: state.quoteNumber,
                totalPrice: null
            };
        }
    }

    get isStep1() {
        return this.currentStep === '1';
    }

    get isStep2() {
        return this.currentStep === '2';
    }

    get isStep3() {
        return this.currentStep === '3';
    }

    get isStep4() {
        return this.currentStep === '4';
    }

    get isStep5() {
        return this.currentStep === '5';
    }

    get showBack() {
        return this.currentStep !== '1' && !this.quoteCreated;
    }

    get showNext() {
        return this.currentStep !== '5' && !this.quoteCreated;
    }

    get nextLabel() {
        return this.currentStep === '4' ? 'Review' : 'Next';
    }

    get commitmentOptions() {
        return COMMITMENT_OPTIONS;
    }

    get offerOptions() {
        return OFFER_OPTIONS;
    }

    get isFibre() {
        return this.offerType === 'Fiber';
    }

    get offerTypeLabel() {
        if (this.offerType === 'Fiber') {
            return 'Fibre & Landline';
        }
        return this.offerType || 'Not selected';
    }

    get hasOfferMissing() {
        return !this.offerType;
    }

    get hasContacts() {
        return this.contactOptions.length > 0;
    }

    get selectedPlan() {
        return (this.plans || []).find(
            (plan) => plan.productId === this.planProductId
        );
    }

    get selectedPlanName() {
        return this.selectedPlan ? this.selectedPlan.name : '';
    }

    get selectedDevice() {
        return (this.devices || []).find(
            (device) => device.productId === this.deviceProductId
        );
    }

    get selectedDeviceName() {
        return this.selectedDevice ? this.selectedDevice.name : 'No device';
    }

    get planOptions() {
        return (this.plans || []).map((plan) => ({
            label: plan.name,
            value: plan.productId
        }));
    }

    get deviceOptions() {
        return [
            { label: 'No device', value: '' },
            ...(this.devices || []).map((device) => ({
                label: device.name,
                value: device.productId
            }))
        ];
    }

    get selectedPlanSummary() {
        const plan = this.selectedPlan;
        if (!plan) {
            return '';
        }
        const parts = [];
        if (plan.dataGb) {
            parts.push(`${plan.dataGb} GB`);
        }
        if (plan.speedMbps) {
            parts.push(`${plan.speedMbps} Mbps`);
        }
        if (plan.specs) {
            parts.push(plan.specs);
        }
        return parts.join(' · ');
    }

    get hasDeviceImage() {
        return Boolean(this.selectedDevice && this.selectedDevice.deviceImageUrl);
    }

    get hasSegmentWarning() {
        return !this.accountSegment;
    }

    get planBlockingText() {
        return blockingText(this.planConfigs);
    }

    get deviceBlockingText() {
        return blockingText(this.deviceConfigs);
    }

    get hasPlanBlocking() {
        return hasBlocking(this.planConfigs);
    }

    get hasDeviceBlocking() {
        return hasBlocking(this.deviceConfigs);
    }

    get activationBlockedText() {
        const plan = this.selectedPlan;
        if (!plan || !plan.activationBlocked) {
            return '';
        }
        return `Activation is blocked until ${plan.earliestActivationDate}.`;
    }

    get hasActivationBlock() {
        return Boolean(this.selectedPlan && this.selectedPlan.activationBlocked);
    }

    get pricingBlockingText() {
        const reasons = [];
        (this.pricing || []).forEach((line) => {
            (line.blockingReasons || []).forEach((reason) => reasons.push(reason));
        });
        return reasons.join(' ');
    }

    get hasPricingBlocking() {
        return (this.pricing || []).some(
            (line) => (line.blockingReasons || []).length > 0
        );
    }

    get canCreateQuote() {
        return (
            !this.isLoading &&
            Boolean(this.offerType) &&
            Boolean(this.planProductId) &&
            this.pricing.length > 0 &&
            !this.hasPricingBlocking &&
            !this.hasActivationBlock &&
            !this.quoteCreated
        );
    }

    get isCreateDisabled() {
        return !this.canCreateQuote;
    }

    get segmentWarning() {
        return this.hasSegmentWarning
            ? 'This Account has no Segment. Segment-specific pricing will not apply until it is set.'
            : '';
    }

    get stepNumber() {
        return Number(this.currentStep);
    }

    get selectedContactLabel() {
        const contact = this.contactOptions.find(
            (option) => option.value === this.contactId
        );
        return contact ? contact.label : '';
    }

    get isContactSyncDisabled() {
        return !this.isAutosync || !this.contactId;
    }

    get contactSyncNote() {
        if (!this.isAutosync) {
            return 'Auto-sync is off. Contact details are read-only in the wizard.';
        }
        return this.contactSaveMessage || '';
    }

    get contactSyncNoteClass() {
        return this.contactSaveError
            ? 'slds-text-color_error slds-m-top_x-small'
            : 'slds-text-color_weak slds-m-top_x-small';
    }

    get quoteWarningText() {
        return this.quoteResult && this.quoteResult.warningReasons
            ? this.quoteResult.warningReasons.join(' ')
            : '';
    }

    get hasQuoteWarnings() {
        return Boolean(this.quoteWarningText);
    }

    handleContactChange(event) {
        this.contactId = event.detail.value;
        this.errorMessage = '';
        this.syncContactFields();
    }

    handleContactEmailChange(event) {
        this.contactEmail = event.detail.value || '';
        this.queueContactSave();
    }

    handleContactPhoneChange(event) {
        this.contactPhone = event.detail.value || '';
        this.queueContactSave();
    }

    syncContactFields() {
        const contact = (this.contactOptions || []).find(
            (option) => option.value === this.contactId
        );
        this.contactEmail = contact ? contact.email || '' : '';
        this.contactPhone = contact ? contact.phone || '' : '';
        this.contactSaveMessage = '';
        this.contactSaveError = false;
        this.contactSavePending = false;
        if (this.contactSaveTimer) {
            clearTimeout(this.contactSaveTimer);
            this.contactSaveTimer = null;
        }
    }

    queueContactSave() {
        if (!this.isAutosync || !this.contactId || !this.sessionId) {
            return;
        }
        this.contactSavePending = true;
        this.contactSaveMessage = 'Saving...';
        this.contactSaveError = false;
        if (this.contactSaveTimer) {
            clearTimeout(this.contactSaveTimer);
        }
        this.contactSaveTimer = setTimeout(() => {
            this.flushContactSave();
        }, 700);
    }

    async flushContactSave() {
        if (!this.contactSavePending) {
            return true;
        }
        if (this.contactSaveTimer) {
            clearTimeout(this.contactSaveTimer);
            this.contactSaveTimer = null;
        }
        if (!this.isAutosync || !this.contactId || !this.sessionId) {
            this.contactSavePending = false;
            return true;
        }

        this.contactSavePending = false;
        try {
            const saved = await saveContactDetails({
                sessionId: this.sessionId,
                contactId: this.contactId,
                email: this.contactEmail || null,
                phone: this.contactPhone || null
            });
            if (saved) {
                this.applySavedContact(saved);
            }
            this.contactSaveMessage = 'Saved';
            this.contactSaveError = false;
            return true;
        } catch (error) {
            this.contactSavePending = true;
            this.contactSaveMessage = reduceError(error);
            this.contactSaveError = true;
            this.errorMessage = this.contactSaveMessage;
            return false;
        }
    }

    applySavedContact(saved) {
        const index = (this.contactOptions || []).findIndex(
            (option) => option.value === saved.contactId
        );
        if (index < 0) {
            return;
        }
        const updated = {
            ...this.contactOptions[index],
            email: saved.email || '',
            phone: saved.phone || '',
            detail: saved.email || saved.phone || ''
        };
        const next = [...this.contactOptions];
        next[index] = updated;
        this.contactOptions = next;
    }

    handleOfferTypeChange(event) {
        this.offerType = event.detail.value;
        this.planProductId = null;
        this.deviceProductId = null;
        this.plans = [];
        this.devices = [];
        this.planConfigs = [];
        this.deviceConfigs = [];
        this.pricing = [];
        this.errorMessage = '';
    }

    handleCommitmentChange(event) {
        this.commitmentCode = event.detail.value;
        this.planProductId = null;
        this.planConfigs = [];
        this.pricing = [];
        this.errorMessage = '';
        this.loadPlans();
    }

    handlePostalChange(event) {
        this.postalCode = event.detail.value.trim();
        this.planProductId = null;
        this.planConfigs = [];
        this.pricing = [];
        this.errorMessage = '';
    }

    async handleCheckCoverage() {
        if (!this.postalCode) {
            this.errorMessage = 'Enter a postal code to check fibre coverage.';
            return;
        }
        await this.loadPlans();
    }

    async handlePlanChange(event) {
        this.planProductId = event.detail.value;
        this.planConfigs = [];
        this.pricing = [];
        this.errorMessage = '';
        await this.loadPlanOptions();
    }

    async handleDeviceChange(event) {
        this.deviceProductId = event.detail.value || null;
        this.deviceConfigs = [];
        this.pricing = [];
        this.errorMessage = '';
        if (this.deviceProductId) {
            await this.loadDeviceOptions();
        }
    }

    handleEffectiveDateChange(event) {
        this.effectiveDate = event.detail.value || TODAY;
    }

    async handleNext() {
        if (this.currentStep === '1') {
            const saved = await this.flushContactSave();
            if (!saved) {
                return;
            }
        }
        this.errorMessage = '';
        if (!this.validateCurrentStep()) {
            return;
        }

        if (this.currentStep === '2') {
            await this.loadPlans();
            if (this.isFibre && !this.postalCode) {
                this.currentStep = '3';
                await this.persistState();
                return;
            }
            if (this.plans.length === 0) {
                this.errorMessage =
                    'No plans are available for this offer type and commitment.';
                return;
            }
        }

        if (this.currentStep === '3') {
            if (this.isFibre && !this.postalCode) {
                this.errorMessage =
                    'Enter a postal code and check fibre coverage before continuing.';
                return;
            }
            if (this.plans.length === 0) {
                await this.loadPlans();
            }
            if (!this.planProductId) {
                this.errorMessage = 'Select a plan before continuing.';
                return;
            }
            if (this.hasPlanBlocking) {
                this.errorMessage = this.planBlockingText;
                return;
            }
            await this.loadDevices();
        }

        if (this.currentStep === '4') {
            if (this.hasDeviceBlocking) {
                this.errorMessage = this.deviceBlockingText;
                return;
            }
            await this.loadPricing();
        }

        const nextStep = Math.min(Number(this.currentStep) + 1, 5);
        this.currentStep = String(nextStep);
        await this.persistState();
    }

    async handleBack() {
        this.errorMessage = '';
        const previousStep = Math.max(Number(this.currentStep) - 1, 1);
        this.currentStep = String(previousStep);
        await this.persistState();
        if (previousStep === 3 && this.offerType && this.plans.length === 0) {
            await this.loadPlans(false);
        }
        if (previousStep === 4 && this.devices.length === 0) {
            await this.loadDevices(false);
        }
    }

    validateCurrentStep() {
        if (this.currentStep === '1' && !this.contactId) {
            this.errorMessage = 'Select a Contact before continuing.';
            return false;
        }
        if (this.currentStep === '2' && !this.offerType) {
            this.errorMessage = 'Select an offer type before continuing.';
            return false;
        }
        if (this.currentStep === '3' && !this.planProductId) {
            this.errorMessage = 'Select a plan before continuing.';
            return false;
        }
        return true;
    }

    async loadPlans(showSpinner = true) {
        if (!this.offerType) {
            this.plans = [];
            return;
        }
        if (this.isFibre && !this.postalCode) {
            this.plans = [];
            return;
        }

        if (showSpinner) {
            this.isLoading = true;
        }
        try {
            let result = await getPlans({
                offerType: this.offerType,
                commitmentCode: this.commitmentCode
            });
            if (this.isFibre) {
                result = await filterByEligibility({
                    plans: result,
                    postalCode: this.postalCode
                });
            }
            this.plans = result || [];
            if (
                this.planProductId &&
                !this.plans.some((plan) => plan.productId === this.planProductId)
            ) {
                this.planProductId = null;
                this.planConfigs = [];
            }
            if (this.plans.length === 0) {
                this.errorMessage = this.isFibre
                    ? 'No eligible fibre plans were found for this postal code.'
                    : 'No plans are available for this offer type and commitment.';
            }
        } catch (error) {
            this.errorMessage = reduceError(error);
        } finally {
            if (showSpinner) {
                this.isLoading = false;
            }
        }
    }

    async loadDevices(showSpinner = true) {
        if (showSpinner) {
            this.isLoading = true;
        }
        try {
            this.devices = (await getDevices()) || [];
            if (
                this.deviceProductId &&
                !this.devices.some(
                    (device) => device.productId === this.deviceProductId
                )
            ) {
                this.deviceProductId = null;
                this.deviceConfigs = [];
            }
        } catch (error) {
            this.errorMessage = reduceError(error);
        } finally {
            if (showSpinner) {
                this.isLoading = false;
            }
        }
    }

    async loadPlanOptions() {
        if (!this.planProductId) {
            this.planConfigs = [];
            return;
        }
        try {
            this.planConfigs =
                (await getOptions({
                    productId: this.planProductId,
                    commitmentCode: this.commitmentCode
                })) || [];
        } catch (error) {
            this.errorMessage = reduceError(error);
        }
    }

    async loadDeviceOptions() {
        if (!this.deviceProductId) {
            this.deviceConfigs = [];
            return;
        }
        try {
            this.deviceConfigs =
                (await getOptions({
                    productId: this.deviceProductId,
                    commitmentCode: this.commitmentCode
                })) || [];
        } catch (error) {
            this.errorMessage = reduceError(error);
        }
    }

    async loadPricing() {
        if (!this.planProductId) {
            this.pricing = [];
            this.pricingTotal = 0;
            return;
        }

        this.isLoading = true;
        try {
            const plan = this.selectedPlan;
            const device = this.selectedDevice;
            const requests = [
                getPriceBreakdown({
                    productId: this.planProductId,
                    commitmentCode: this.commitmentCode,
                    segment: this.accountSegment || null,
                    effectiveDate: this.effectiveDate,
                    companionScopes: device ? [device.family] : []
                })
            ];
            if (device) {
                requests.push(
                    getPriceBreakdown({
                        productId: device.productId,
                        commitmentCode: this.commitmentCode,
                        segment: this.accountSegment || null,
                        effectiveDate: this.effectiveDate,
                        companionScopes: plan ? [plan.family] : []
                    })
                );
            }

            const breakdowns = await Promise.all(requests);
            this.pricing = breakdowns.map((line) => ({
                ...line,
                hasBlockingReasons: (line.blockingReasons || []).length > 0,
                blockingText: (line.blockingReasons || []).join(' '),
                hasWarningReasons: (line.warningReasons || []).length > 0,
                warningText: (line.warningReasons || []).join(' ')
            }));
            this.pricingTotal = this.pricing.reduce(
                (total, line) => total + Number(line.finalPrice || 0),
                0
            );
        } catch (error) {
            this.errorMessage = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleCreateQuote() {
        if (!this.offerType) {
            this.errorMessage =
                'Select an offer before creating the quote.';
            return;
        }
        if (!this.canCreateQuote) {
            return;
        }
        this.errorMessage = '';
        this.isLoading = true;
        try {
            const result = await createQuote({
                request: {
                    accountId: this.accountId,
                    contactId: this.contactId,
                    opportunityId: this.opportunityId || null,
                    wizardSessionId: this.sessionId,
                    offerType: this.offerType,
                    planProductId: this.planProductId,
                    deviceProductId: this.deviceProductId || null,
                    commitmentCode: this.commitmentCode,
                    segment: this.accountSegment || null,
                    effectiveDate: this.effectiveDate,
                    postalCode: this.postalCode || null,
                    portalSubmitted: false
                }
            });
            this.quoteResult = result;
            this.quoteCreated = true;
        } catch (error) {
            this.errorMessage = reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleGoToOffer() {
        this.errorMessage = '';
        this.currentStep = '2';
        await this.persistState();
        await this.loadPlans(false);
    }

    handleViewQuote() {
        if (!this.quoteResult || !this.quoteResult.quoteId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.quoteResult.quoteId,
                objectApiName: 'Quote',
                actionName: 'view'
            }
        });
    }

    async persistState() {
        if (!this.sessionId) {
            return;
        }
        try {
            await saveWizard({
                state: {
                    sessionId: this.sessionId,
                    accountId: this.accountId,
                    contactId: this.contactId || null,
                    opportunityId: this.opportunityId || null,
                    offerType: this.offerType || null,
                    planProductId: this.planProductId || null,
                    deviceProductId: this.deviceProductId || null,
                    commitmentCode: this.commitmentCode,
                    step: Number(this.currentStep),
                    stateJson: JSON.stringify({
                        postalCode: this.postalCode || null,
                        effectiveDate: this.effectiveDate
                    })
                }
            });
        } catch (error) {
            this.errorMessage = reduceError(error);
        }
    }
}

function hasBlocking(configs) {
    return (configs || []).some((config) => config.blocking);
}

function blockingText(configs) {
    return (configs || [])
        .filter((config) => config.blocking)
        .map((config) => config.message)
        .filter(Boolean)
        .join(' ');
}

function parseJson(value) {
    if (!value) {
        return {};
    }
    try {
        return JSON.parse(value);
    } catch (error) {
        return {};
    }
}

function localDate() {
    const now = new Date();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${now.getFullYear()}-${month}-${day}`;
}

function reduceError(error) {
    if (error && error.body) {
        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (error.body.message) {
            return error.body.message;
        }
        if (error.body.pageErrors && error.body.pageErrors.length) {
            return error.body.pageErrors[0].message;
        }
        if (error.body.fieldErrors) {
            const messages = [];
            Object.values(error.body.fieldErrors).forEach((fieldErrors) => {
                fieldErrors.forEach((fieldError) => messages.push(fieldError.message));
            });
            if (messages.length) {
                return messages.join(', ');
            }
        }
    }
    return error && error.message ? error.message : 'Unexpected error';
}
