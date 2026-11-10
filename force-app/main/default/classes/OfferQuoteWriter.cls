/**
 * Orchestrates quote persistence after pricing has been resolved. All DML
 * uses USER_MODE; the caller owns the surrounding savepoint.
 */
public with sharing class OfferQuoteWriter {
    public static OfferBuilderService.OfferResult write(
        OfferContext context,
        OfferCatalog catalog
    ) {
        OfferQuotePricing.PricedOffer priced =
            OfferQuotePricing.price(context, catalog);
        Opportunity opportunity = ensureOpportunity(
            context,
            catalog,
            priced.pricebookId
        );
        Quote quote = insertQuote(
            context,
            catalog,
            opportunity,
            priced.pricebookId
        );
        List<QuoteLineItem> lines = insertLines(quote, priced.breakdowns);
        updateWizard(
            context,
            catalog,
            quote,
            opportunity,
            priced.breakdownJson
        );
        return OfferQuoteResult.build(
            quote,
            opportunity,
            priced.pricebookId,
            lines,
            priced.breakdowns,
            priced.breakdownJson
        );
    }

    private static Opportunity ensureOpportunity(
        OfferContext context,
        OfferCatalog catalog,
        Id pricebookId
    ) {
        if (context.opportunity != null) {
            return context.opportunity;
        }

        Opportunity opportunity = new Opportunity(
            Name = OfferQuoteText.opportunityName(
                context.account,
                context.offerType
            ),
            AccountId = context.accountId,
            Primary_Contact__c = context.contactId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pricebookId,
            Journey_Step__c = 'Quoting',
            Eligibility_Checked__c = catalog.fiber,
            Portal_Source__c = context.selection.portalSubmitted == true
        );
        try {
            Database.insert(opportunity, AccessLevel.USER_MODE);
        } catch (DmlException error) {
            throw new OfferBuilderService.OfferException(
                'Could not create the opportunity: ' + dmlMessage(error)
            );
        }
        return opportunity;
    }

    private static Quote insertQuote(
        OfferContext context,
        OfferCatalog catalog,
        Opportunity opportunity,
        Id pricebookId
    ) {
        Quote quote = new Quote(
            Name = OfferQuoteText.quoteName(
                context.account,
                catalog.plan.name,
                context.commitmentCode
            ),
            OpportunityId = opportunity.Id,
            Pricebook2Id = pricebookId,
            ContactId = context.contactId,
            Status = 'Draft',
            ExpirationDate = Date.today().addDays(30),
            Description = OfferQuoteText.quoteDescription(
                catalog.plan,
                catalog.device,
                context.commitmentCode
            ),
            Wizard_Session__c = context.wizard == null
                ? null
                : context.wizard.Id,
            Portal_Submitted__c = context.selection.portalSubmitted == true
        );
        try {
            Database.insert(quote, AccessLevel.USER_MODE);
        } catch (DmlException error) {
            throw new OfferBuilderService.OfferException(
                'Could not create the quote: ' + dmlMessage(error)
            );
        }
        return quote;
    }

    private static List<QuoteLineItem> insertLines(
        Quote quote,
        List<PricingService.PriceBreakdown> breakdowns
    ) {
        List<QuoteLineItem> lines = new List<QuoteLineItem>();
        for (Integer i = 0; i < breakdowns.size(); i++) {
            PricingService.PriceBreakdown breakdown = breakdowns[i];
            lines.add(new QuoteLineItem(
                QuoteId = quote.Id,
                PricebookEntryId = breakdown.pricebookEntryId,
                Product2Id = breakdown.productId,
                Quantity = 1,
                UnitPrice = breakdown.finalPrice,
                Discount = 0,
                Description = OfferQuoteText.lineDescription(breakdown),
                Commitment_Option_Code__c = breakdown.commitmentCode,
                Subscription_Key__c = OfferQuoteText.subscriptionKey(quote, i)
            ));
        }
        try {
            Database.insert(lines, AccessLevel.USER_MODE);
        } catch (DmlException error) {
            throw new OfferBuilderService.OfferException(
                'Could not create the quote lines: ' + dmlMessage(error)
            );
        }
        return lines;
    }

    private static void updateWizard(
        OfferContext context,
        OfferCatalog catalog,
        Quote quote,
        Opportunity opportunity,
        String breakdownJson
    ) {
        if (context.wizard == null) {
            return;
        }
        context.wizard.Account__c = context.accountId;
        context.wizard.Contact__c = context.contactId;
        context.wizard.Opportunity__c = opportunity.Id;
        context.wizard.Product__c = catalog.plan.productId;
        context.wizard.Device__c = catalog.device == null
            ? null
            : catalog.device.productId;
        context.wizard.Offer_Type__c = context.offerType;
        context.wizard.Commitment_Code__c = context.commitmentCode;
        context.wizard.Quote__c = quote.Id;
        context.wizard.Step__c = 5;
        context.wizard.Is_Active__c = true;
        context.wizard.Last_Activity_On__c = DateTime.now();
        context.wizard.Expires_On__c = Date.today().addDays(7);
        context.wizard.Price_Breakdown__c = breakdownJson;
        try {
            Database.update(context.wizard, AccessLevel.USER_MODE);
        } catch (DmlException error) {
            throw new OfferBuilderService.OfferException(
                'Could not update the wizard session: ' + dmlMessage(error)
            );
        }
    }

    private static String dmlMessage(DmlException error) {
        return error.getNumDml() > 0
            ? error.getDmlMessage(0)
            : error.getMessage();
    }
}
