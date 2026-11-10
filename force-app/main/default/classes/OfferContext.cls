/**
 * Resolves and validates the customer, wizard, and opportunity context for an
 * offer selection. This class is read-only and performs no DML.
 */
public with sharing class OfferContext {
    private static final List<String> OFFER_TYPES = new List<String>{
        'Mobile',
        'Fiber',
        'Landline'
    };
    private static final Set<String> COMMITMENT_CODES = new Set<String>{
        'NOCOMMIT',
        'COMMIT12',
        'COMMIT24'
    };

    public OfferBuilderService.Selection selection;
    public String offerType;
    public String commitmentCode;
    public Date effectiveDate;
    public Subscription_Wizard_State__c wizard;
    public Opportunity opportunity;
    public Account account;
    public Contact contact;
    public Id accountId;
    public Id contactId;
    public Id opportunityId;
    public String segment;

    public static OfferContext resolve(
        OfferBuilderService.Selection selection
    ) {
        if (selection == null) {
            throw new OfferBuilderService.OfferException(
                'Offer selection is required.'
            );
        }

        OfferContext context = new OfferContext();
        context.selection = selection;
        context.offerType = normalizeOfferType(selection.offerType);
        context.commitmentCode = normalizeCommitment(selection.commitmentCode);
        context.effectiveDate = selection.effectiveDate == null
            ? Date.today()
            : selection.effectiveDate;
        context.wizard = findWizard(selection.wizardSessionId);
        context.accountId = firstId(
            selection.accountId,
            context.wizard == null ? null : context.wizard.Account__c
        );
        context.contactId = firstId(
            selection.contactId,
            context.wizard == null ? null : context.wizard.Contact__c
        );
        context.opportunityId = firstId(
            selection.opportunityId,
            context.wizard == null ? null : context.wizard.Opportunity__c
        );

        if (context.accountId == null && context.opportunityId == null) {
            throw new OfferBuilderService.OfferException(
                'Account or opportunity is required.'
            );
        }
        resolveCustomer(context);
        if (context.wizard != null) {
            validateWizard(context);
        }

        context.segment = String.isBlank(selection.segment)
            ? context.account.Segment__c
            : selection.segment;
        return context;
    }

    private static void resolveCustomer(OfferContext context) {
        context.opportunity = findOpportunity(context.opportunityId);
        if (context.opportunity != null) {
            if (context.accountId == null) {
                context.accountId = context.opportunity.AccountId;
            } else if (context.opportunity.AccountId != context.accountId) {
                throw new OfferBuilderService.OfferException(
                    'The opportunity does not belong to the selected account.'
                );
            }
            if (context.contactId == null) {
                context.contactId = context.opportunity.Primary_Contact__c;
            }
        }

        context.account = requireAccount(context.accountId);
        context.contact = requireContact(context.contactId);
        if (context.contact.AccountId != context.accountId) {
            throw new OfferBuilderService.OfferException(
                'The contact does not belong to the selected account.'
            );
        }
    }

    private static Account requireAccount(Id accountId) {
        if (accountId == null) {
            throw new OfferBuilderService.OfferException(
                'Account is required.'
            );
        }
        Account account = findAccount(accountId);
        if (account == null) {
            throw new OfferBuilderService.OfferException(
                'Account not found: ' + accountId
            );
        }
        return account;
    }

    private static Contact requireContact(Id contactId) {
        if (contactId == null) {
            throw new OfferBuilderService.OfferException(
                'Contact is required.'
            );
        }
        Contact contact = findContact(contactId);
        if (contact == null) {
            throw new OfferBuilderService.OfferException(
                'Contact not found: ' + contactId
            );
        }
        return contact;
    }

    private static Subscription_Wizard_State__c findWizard(Id wizardId) {
        if (wizardId == null) {
            return null;
        }
        List<Subscription_Wizard_State__c> rows = [
            SELECT Id, Account__c, Contact__c, Opportunity__c
            FROM Subscription_Wizard_State__c
            WHERE Id = :wizardId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new OfferBuilderService.OfferException(
                'Wizard session not found: ' + wizardId
            );
        }
        return rows[0];
    }

    private static Opportunity findOpportunity(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }
        List<Opportunity> rows = [
            SELECT Id, AccountId, Primary_Contact__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new OfferBuilderService.OfferException(
                'Opportunity not found: ' + opportunityId
            );
        }
        return rows[0];
    }

    private static Account findAccount(Id accountId) {
        List<Account> rows = [
            SELECT Id, Name, Segment__c
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static Contact findContact(Id contactId) {
        List<Contact> rows = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Id = :contactId
            WITH USER_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static void validateWizard(OfferContext context) {
        Subscription_Wizard_State__c wizard = context.wizard;
        if (wizard.Account__c != null && wizard.Account__c != context.accountId) {
            throw new OfferBuilderService.OfferException(
                'The wizard session does not belong to the selected account.'
            );
        }
        if (wizard.Contact__c != null && wizard.Contact__c != context.contactId) {
            throw new OfferBuilderService.OfferException(
                'The wizard session does not belong to the selected contact.'
            );
        }
        if (wizard.Opportunity__c != null
            && wizard.Opportunity__c != context.opportunityId) {
            throw new OfferBuilderService.OfferException(
                'The wizard session does not belong to the selected opportunity.'
            );
        }
    }

    private static Id firstId(Id first, Id second) {
        return first == null ? second : first;
    }

    private static String normalizeOfferType(String offerType) {
        if (String.isBlank(offerType)) {
            throw new OfferBuilderService.OfferException(
                'Offer type is required.'
            );
        }
        String normalized = offerType.trim();
        for (String allowed : OFFER_TYPES) {
            if (allowed.equalsIgnoreCase(normalized)) {
                return allowed;
            }
        }
        throw new OfferBuilderService.OfferException(
            'Unsupported offer type: ' + offerType
        );
    }

    private static String normalizeCommitment(String commitmentCode) {
        String normalized = PricingScope.normalizeCommitment(commitmentCode);
        if (!COMMITMENT_CODES.contains(normalized)) {
            throw new OfferBuilderService.OfferException(
                'Unsupported commitment option: ' + commitmentCode
            );
        }
        return normalized;
    }
}
