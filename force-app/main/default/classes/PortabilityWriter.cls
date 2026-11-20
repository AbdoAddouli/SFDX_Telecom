/**
 * Bulk write path for UC-LIF-07. Only Subscription, Case and
 * Customer_Request__c are written. The MSISDN is touched only in apply().
 */
public with sharing class PortabilityWriter {
    public static void stampRequests(List<PortabilityContext> contexts) {
        if (contexts == null || contexts.isEmpty()) {
            return;
        }
        List<Customer_Request__c> requests = new List<Customer_Request__c>();
        for (PortabilityContext context : contexts) {
            requests.add(
                new Customer_Request__c(
                    Id = context.request.Id,
                    Requested_MSISDN__c = context.requestedMsisdn,
                    Port_Direction__c = context.direction,
                    Previous_MSISDN__c = context.previousMsisdn,
                    Port_Request_Reference__c = context.requestReference,
                    Resolution_Summary__c = (
                        'Port request submitted to BSS for ' +
                        context.direction +
                        '. Reference ' +
                        context.requestReference +
                        '. MSISDN is unchanged until donor confirmation.'
                    ).left(1000)
                )
            );
        }
        Database.update(requests, true);
    }

    public static void apply(List<PortabilityContext> contexts) {
        if (contexts == null || contexts.isEmpty()) {
            return;
        }
        Datetime now = Datetime.now();
        List<Subscription__c> subscriptions = new List<Subscription__c>();
        List<Customer_Request__c> requests = new List<Customer_Request__c>();
        List<Case> cases = new List<Case>();

        for (PortabilityContext context : contexts) {
            Subscription__c subscriptionUpdate = new Subscription__c(
                Id = context.subscription.Id,
                Last_Sync_DateTime__c = now
            );
            subscriptionUpdate.MSISDN__c = context.targetMsisdn;
            subscriptions.add(subscriptionUpdate);

            requests.add(
                new Customer_Request__c(
                    Id = context.request.Id,
                    Status__c = PortabilityPolicy.STATUS_COMPLETED,
                    Completed_On__c = now,
                    Port_Confirmation_Reference__c = context.confirmationReference,
                    Previous_MSISDN__c = context.previousMsisdn,
                    Resolution_Summary__c = resolutionSummary(context)
                )
            );
            if (context.request.Case__c != null) {
                cases.add(
                    new Case(
                        Id = context.request.Case__c,
                        Status = PortabilityPolicy.CASE_CLOSED
                    )
                );
            }
        }

        Database.update(subscriptions, true);
        Database.update(requests, true);
        updateCases(cases);
    }

    public static void reject(List<PortabilityContext> contexts) {
        if (contexts == null || contexts.isEmpty()) {
            return;
        }
        List<Customer_Request__c> requests = new List<Customer_Request__c>();
        List<Case> cases = new List<Case>();

        for (PortabilityContext context : contexts) {
            requests.add(
                new Customer_Request__c(
                    Id = context.request.Id,
                    Status__c = PortabilityPolicy.STATUS_REJECTED,
                    Rejection_Reason__c = context.confirmation.rejectionReason.left(1000),
                    Port_Confirmation_Reference__c = context.confirmationReference,
                    Resolution_Summary__c = (
                        'Donor rejected the port request. Reason: ' +
                        context.confirmation.rejectionReason +
                        '. MSISDN is unchanged.'
                    ).left(1000)
                )
            );
            if (context.request.Case__c != null) {
                cases.add(
                    new Case(
                        Id = context.request.Case__c,
                        Status = PortabilityPolicy.CASE_CLOSED
                    )
                );
            }
        }

        Database.update(requests, true);
        updateCases(cases);
    }

    private static String resolutionSummary(PortabilityContext context) {
        if (PortabilityPolicy.DIRECTION_OUTBOUND == context.direction) {
            return (
                'Outbound port confirmed with reference ' +
                context.confirmationReference +
                '. Previous MSISDN ' +
                context.previousMsisdn +
                ' has been released.'
            ).left(1000);
        }
        String previous =
            String.isBlank(context.previousMsisdn)
                ? '(none)'
                : context.previousMsisdn;
        return (
            'Inbound port confirmed with reference ' +
            context.confirmationReference +
            '. MSISDN changed from ' +
            previous +
            ' to ' +
            context.targetMsisdn +
            '.'
        ).left(1000);
    }

    private static void updateCases(List<Case> cases) {
        if (cases == null || cases.isEmpty()) {
            return;
        }
        Database.update(cases, true);
    }
}
