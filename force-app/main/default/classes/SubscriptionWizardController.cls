/**
 * Server-side state boundary for the five-step subscription wizard.
 *
 * The component owns presentation; this controller owns resumable wizard state,
 * account/contact context, and user-mode DML. Catalogue and pricing reads stay
 * in CatalogQueryService, and quote creation stays in OfferBuilderService.
 */
public with sharing class SubscriptionWizardController {
    private static final Integer FIRST_STEP = 1;
    private static final Integer LAST_STEP = 5;
    private static final Integer SESSION_DAYS = 7;

    /**
     * Aura deserializes custom-class parameters into properties only. Keep
     * this DTO as get/set properties so save() receives the client payload.
     */
    public class WizardState {
        @AuraEnabled public Id sessionId { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public Id opportunityId { get; set; }
        @AuraEnabled public String offerType { get; set; }
        @AuraEnabled public Id planProductId { get; set; }
        @AuraEnabled public Id deviceProductId { get; set; }
        @AuraEnabled public String commitmentCode { get; set; }
        @AuraEnabled public Integer step { get; set; }
        @AuraEnabled public String stateJson { get; set; }
        @AuraEnabled public Id quoteId { get; set; }
        @AuraEnabled public String quoteNumber { get; set; }
    }

    public class AccountContext {
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public String segment { get; set; }
        @AuraEnabled public Boolean isAutosync { get; set; }
        @AuraEnabled public List<ContactOption> contacts { get; set; }
    }

    public class ContactOption {
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String phone { get; set; }
    }

    /**
     * Aura-facing quote request.
     *
     * Aura only deserializes properties, not plain public fields, when binding
     * a custom class parameter. This DTO mirrors OfferBuilderService.Selection
     * so the Flow/invocable DTO can keep its public fields.
     */
    public class QuoteRequest {
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public Id opportunityId { get; set; }
        @AuraEnabled public Id wizardSessionId { get; set; }
        @AuraEnabled public String offerType { get; set; }
        @AuraEnabled public Id planProductId { get; set; }
        @AuraEnabled public Id deviceProductId { get; set; }
        @AuraEnabled public String commitmentCode { get; set; }
        @AuraEnabled public String segment { get; set; }
        @AuraEnabled public Date effectiveDate { get; set; }
        @AuraEnabled public String postalCode { get; set; }
        @AuraEnabled public Boolean portalSubmitted { get; set; }
    }

    @AuraEnabled
    public static WizardState start(
        Id accountId,
        Id contactId,
        Id opportunityId,
        Id sessionId
    ) {
        if (sessionId != null) {
            Subscription_Wizard_State__c existing = findSession(sessionId);
            if (existing == null) {
                throw error('Wizard session not found: ' + sessionId);
            }
            touch(existing);
            return toState(existing);
        }

        if (accountId == null) {
            throw error('Account is required to start the wizard.');
        }

        Subscription_Wizard_State__c existing = findActive(accountId);
        if (existing != null) {
            if (contactId != null) {
                existing.Contact__c = contactId;
            }
            if (opportunityId != null) {
                existing.Opportunity__c = opportunityId;
            }
            touch(existing);
            return toState(existing);
        }

        deactivateOtherSessions();
        Subscription_Wizard_State__c created = new Subscription_Wizard_State__c(
            Account__c = accountId,
            Contact__c = contactId,
            Opportunity__c = opportunityId,
            Advisor__c = UserInfo.getUserId(),
            Step__c = FIRST_STEP,
            State_Json__c = '{}',
            Is_Active__c = true,
            Last_Activity_On__c = DateTime.now(),
            Expires_On__c = Date.today().addDays(SESSION_DAYS)
        );
        try {
            Database.insert(created, AccessLevel.USER_MODE);
        } catch (DmlException dmlError) {
            throw error(dmlMessage(dmlError));
        }
        return toState(created);
    }

    @AuraEnabled
    public static void save(WizardState state) {
        if (state == null || state.sessionId == null) {
            throw error('Wizard session is required.');
        }

        Subscription_Wizard_State__c existing = findSession(state.sessionId);
        if (existing == null) {
            throw error('Wizard session not found: ' + state.sessionId);
        }

        existing.Account__c = state.accountId;
        existing.Contact__c = state.contactId;
        existing.Opportunity__c = state.opportunityId;
        existing.Offer_Type__c = state.offerType;
        existing.Product__c = state.planProductId;
        existing.Device__c = state.deviceProductId;
        existing.Commitment_Code__c = state.commitmentCode;
        existing.Step__c = normalizeStep(state.step);
        existing.State_Json__c = String.isBlank(state.stateJson)
            ? '{}'
            : state.stateJson;
        existing.Is_Active__c = true;
        existing.Last_Activity_On__c = DateTime.now();
        existing.Expires_On__c = Date.today().addDays(SESSION_DAYS);

        try {
            Database.update(existing, AccessLevel.USER_MODE);
        } catch (DmlException dmlError) {
            throw error(dmlMessage(dmlError));
        }
    }

    /**
     * Aura-facing quote entry point. The request is mapped onto the public
     * OfferBuilderService.Selection DTO, which stays the single pricing and
     * persistence path for both Aura and Flow.
     */
    @AuraEnabled
    public static OfferBuilderService.OfferResult createQuote(
        QuoteRequest request
    ) {
        if (request == null) {
            throw error('Offer selection is required.');
        }

        OfferBuilderService.Selection selection =
            new OfferBuilderService.Selection();
        selection.accountId = request.accountId;
        selection.contactId = request.contactId;
        selection.opportunityId = request.opportunityId;
        selection.wizardSessionId = request.wizardSessionId;
        selection.offerType = request.offerType;
        selection.planProductId = request.planProductId;
        selection.deviceProductId = request.deviceProductId;
        selection.commitmentCode = request.commitmentCode;
        selection.segment = request.segment;
        selection.effectiveDate = request.effectiveDate;
        selection.postalCode = request.postalCode;
        selection.portalSubmitted = request.portalSubmitted == true;

        return OfferBuilderService.createQuote(selection);
    }

    @AuraEnabled(cacheable=true)
    public static AccountContext getAccountContext(Id accountId) {
        if (accountId == null) {
            throw error('Account id is required.');
        }

        List<Account> accounts = [
            SELECT Id, Name, Segment__c
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            throw error('Account not found: ' + accountId);
        }

        AccountContext context = new AccountContext();
        context.accountId = accounts[0].Id;
        context.accountName = accounts[0].Name;
        context.segment = accounts[0].Segment__c;
        context.isAutosync = isAutosyncEnabled();
        context.contacts = new List<ContactOption>();
        for (Contact contact : [
            SELECT Id, Name, Email, Phone
            FROM Contact
            WHERE AccountId = :accountId
            WITH USER_MODE
            ORDER BY Name
            LIMIT 200
        ]) {
            context.contacts.add(toContactOption(contact));
        }
        return context;
    }

    /**
     * Debounced Step 1 write-back. Advisors have read-only Account access, so
     * only Contact email and phone are writable here. The feature flag remains
     * authoritative on the server so a stale client cannot bypass it.
     */
    @AuraEnabled
    public static ContactOption saveContactDetails(
        Id sessionId,
        Id contactId,
        String email,
        String phone
    ) {
        if (sessionId == null) {
            throw error('Wizard session is required.');
        }
        if (contactId == null) {
            throw error('Contact is required.');
        }
        if (!isAutosyncEnabled()) {
            throw error('Auto-sync is disabled.');
        }

        Subscription_Wizard_State__c session = findSession(sessionId);
        if (session == null) {
            throw error('Wizard session not found: ' + sessionId);
        }

        List<Contact> contacts = [
            SELECT Id, Name, AccountId, Email, Phone
            FROM Contact
            WHERE Id = :contactId
            WITH USER_MODE
            LIMIT 1
        ];
        if (contacts.isEmpty()) {
            throw error('Contact not found: ' + contactId);
        }

        Contact contact = contacts[0];
        if (contact.AccountId != session.Account__c) {
            throw error('Contact does not belong to this account.');
        }

        String nextEmail = String.isBlank(email) ? null : email.trim();
        String nextPhone = String.isBlank(phone) ? null : phone.trim();
        if (contact.Email == nextEmail && contact.Phone == nextPhone) {
            return toContactOption(contact);
        }

        contact.Email = nextEmail;
        contact.Phone = nextPhone;

        Savepoint checkpoint = Database.setSavepoint();
        try {
            Database.update(contact, AccessLevel.USER_MODE);
        } catch (DmlException dmlError) {
            Database.rollback(checkpoint);
            throw error(dmlMessage(dmlError));
        }

        return toContactOption(contact);
    }

    private static Subscription_Wizard_State__c findSession(Id sessionId) {
        List<Subscription_Wizard_State__c> rows = [
            SELECT Id, Account__c, Contact__c, Opportunity__c, Offer_Type__c,
                Product__c, Device__c, Commitment_Code__c, Step__c, State_Json__c,
                Quote__c, Quote__r.QuoteNumber
            FROM Subscription_Wizard_State__c
            WHERE Id = :sessionId
                AND Advisor__c = :UserInfo.getUserId()
            WITH USER_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Subscription_Wizard_State__c findActive(Id accountId) {
        List<Subscription_Wizard_State__c> rows = [
            SELECT Id, Account__c, Contact__c, Opportunity__c, Offer_Type__c,
                Product__c, Device__c, Commitment_Code__c, Step__c, State_Json__c,
                Quote__c, Quote__r.QuoteNumber
            FROM Subscription_Wizard_State__c
            WHERE Advisor__c = :UserInfo.getUserId()
                AND Account__c = :accountId
                AND Is_Active__c = true
                AND (Expires_On__c = null OR Expires_On__c >= :Date.today())
            WITH USER_MODE
            ORDER BY Last_Activity_On__c DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static void deactivateOtherSessions() {
        List<Subscription_Wizard_State__c> sessions = [
            SELECT Id
            FROM Subscription_Wizard_State__c
            WHERE Advisor__c = :UserInfo.getUserId()
                AND Is_Active__c = true
            WITH USER_MODE
            LIMIT 200
        ];
        if (sessions.isEmpty()) {
            return;
        }
        for (Subscription_Wizard_State__c session : sessions) {
            session.Is_Active__c = false;
        }
        try {
            Database.update(sessions, AccessLevel.USER_MODE);
        } catch (DmlException dmlError) {
            throw error(dmlMessage(dmlError));
        }
    }

    private static void touch(Subscription_Wizard_State__c session) {
        session.Last_Activity_On__c = DateTime.now();
        session.Expires_On__c = Date.today().addDays(SESSION_DAYS);
        try {
            Database.update(session, AccessLevel.USER_MODE);
        } catch (DmlException dmlError) {
            throw error(dmlMessage(dmlError));
        }
    }

    private static WizardState toState(Subscription_Wizard_State__c record) {
        WizardState state = new WizardState();
        state.sessionId = record.Id;
        state.accountId = record.Account__c;
        state.contactId = record.Contact__c;
        state.opportunityId = record.Opportunity__c;
        state.offerType = record.Offer_Type__c;
        state.planProductId = record.Product__c;
        state.deviceProductId = record.Device__c;
        state.commitmentCode = record.Commitment_Code__c;
        state.step = normalizeStep(record.Step__c);
        state.stateJson = record.State_Json__c;
        state.quoteId = record.Quote__c;
        state.quoteNumber = record.Quote__r == null
            ? null
            : record.Quote__r.QuoteNumber;
        return state;
    }

    private static ContactOption toContactOption(Contact contact) {
        ContactOption option = new ContactOption();
        option.contactId = contact.Id;
        option.name = contact.Name;
        option.email = contact.Email;
        option.phone = contact.Phone;
        return option;
    }

    private static Boolean isAutosyncEnabled() {
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getInstance();
        if (flags == null || flags.Is_Autosync__c == null) {
            return true;
        }
        return flags.Is_Autosync__c;
    }

    private static Integer normalizeStep(Decimal step) {
        if (step == null) {
            return FIRST_STEP;
        }
        Integer value = step.intValue();
        if (value < FIRST_STEP) {
            return FIRST_STEP;
        }
        return value > LAST_STEP ? LAST_STEP : value;
    }

    private static String dmlMessage(DmlException dmlError) {
        return dmlError.getNumDml() > 0
            ? dmlError.getDmlMessage(0)
            : dmlError.getMessage();
    }

    private static AuraHandledException error(String message) {
        AuraHandledException handled = new AuraHandledException(message);
        handled.setMessage(message);
        return handled;
    }
}
