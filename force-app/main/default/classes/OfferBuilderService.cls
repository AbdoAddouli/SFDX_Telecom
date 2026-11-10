/**
 * Public entry point for quote creation.
 *
 * This class owns the Aura/Flow API, the public DTOs, the savepoint boundary,
 * and error translation. Customer resolution, catalogue validation, and
 * persistence live in dedicated collaborators so this facade stays small.
 */
public with sharing class OfferBuilderService {
    public class OfferException extends Exception {}

    public class Selection {
        @AuraEnabled @InvocableVariable public Id accountId;
        @AuraEnabled @InvocableVariable public Id contactId;
        @AuraEnabled @InvocableVariable public Id opportunityId;
        @AuraEnabled @InvocableVariable public Id wizardSessionId;
        @AuraEnabled @InvocableVariable public String offerType;
        @AuraEnabled @InvocableVariable public Id planProductId;
        @AuraEnabled @InvocableVariable public Id deviceProductId;
        @AuraEnabled @InvocableVariable public String commitmentCode;
        @AuraEnabled @InvocableVariable public String segment;
        @AuraEnabled @InvocableVariable public Date effectiveDate;
        @AuraEnabled @InvocableVariable public String postalCode;
        @AuraEnabled @InvocableVariable public Boolean portalSubmitted;
    }

    public class OfferResult {
        @AuraEnabled @InvocableVariable public Id quoteId;
        @AuraEnabled @InvocableVariable public String quoteNumber;
        @AuraEnabled @InvocableVariable public String quoteName;
        @AuraEnabled @InvocableVariable public Id opportunityId;
        @AuraEnabled @InvocableVariable public Id pricebookId;
        @AuraEnabled @InvocableVariable public Decimal totalListPrice;
        @AuraEnabled @InvocableVariable public Decimal totalAdjustment;
        @AuraEnabled @InvocableVariable public Decimal totalPrice;
        @AuraEnabled @InvocableVariable public Integer lineCount;
        @AuraEnabled @InvocableVariable public List<Id> quoteLineItemIds;
        @AuraEnabled @InvocableVariable public List<String> warningReasons;
        @AuraEnabled @InvocableVariable public String priceBreakdownJson;

        public OfferResult() {
            this.totalListPrice = 0;
            this.totalAdjustment = 0;
            this.totalPrice = 0;
            this.lineCount = 0;
            this.quoteLineItemIds = new List<Id>();
            this.warningReasons = new List<String>();
        }
    }

    @AuraEnabled
    public static OfferResult createQuote(Selection selection) {
        Savepoint checkpoint = Database.setSavepoint();
        try {
            OfferContext context = OfferContext.resolve(selection);
            OfferCatalog catalog = OfferCatalog.resolve(context);
            return OfferQuoteWriter.write(context, catalog);
        } catch (Exception error) {
            Database.rollback(checkpoint);
            throw translate(error);
        }
    }

    /**
     * Flow-callable wrapper. Each selection is an independent quote and keeps
     * its own savepoint.
     */
    @InvocableMethod(
        label='Create Quote from Offer Selection'
        description='Creates a priced Quote and QuoteLineItems from a wizard selection.'
    )
    public static List<OfferResult> createQuotes(List<Selection> selections) {
        List<OfferResult> results = new List<OfferResult>();
        if (selections == null) {
            return results;
        }
        for (Selection selection : selections) {
            results.add(createQuote(selection));
        }
        return results;
    }

    private static OfferException translate(Exception error) {
        if (error instanceof OfferException) {
            return (OfferException) error;
        }
        return new OfferException(
            'Could not create the quote: ' + error.getMessage()
        );
    }
}
