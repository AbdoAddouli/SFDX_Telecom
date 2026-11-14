/**
 * UC-COM-06: chunked activation for BSS batches.
 *
 * A batch is split into independent queueable jobs of at most
 * ActivationService.MAX_ORDERS_PER_CALL orders. That keeps every transaction
 * inside the 100 SOQL / 150 DML budget and gives each order its own savepoint.
 * A 500-order batch uses 50 jobs, the queueable per-transaction limit; larger
 * requests are rejected so the caller can split them.
 *
 * Every chunk summary and every order log shares one correlation ID.
 */
public with sharing class ActivationBatchJob implements Queueable {
    private static final String OPERATION = 'activationBatch';
    private static final String ENDPOINT = 'internal://activation/batch';
    public static final Integer MAX_ORDERS_PER_BATCH = 500;

    private List<Id> chunk;
    private String batchCorrelationId;
    private Integer chunkNumber;
    private Integer chunkCount;
    private Integer expectedCount;
    private DateTime startedAt;

    public class ActivationBatchException extends Exception {
    }

    private ActivationBatchJob(
        List<Id> chunk,
        String correlationId,
        Integer chunkNumber,
        Integer chunkCount,
        Integer expectedCount,
        DateTime startedAt
    ) {
        this.chunk = chunk == null ? new List<Id>() : chunk;
        this.batchCorrelationId = String.isBlank(correlationId)
            ? String.valueOf(UUID.randomUUID())
            : correlationId;
        this.chunkNumber = chunkNumber;
        this.chunkCount = chunkCount;
        this.expectedCount = expectedCount;
        this.startedAt = startedAt == null ? System.now() : startedAt;
    }

    /**
     * Enqueues one queueable job per safe chunk. Callers must use this method
     * rather than System.enqueueJob directly so the chunk size and the 500-order
     * ceiling are always enforced.
     */
    public static Id enqueue(Set<Id> orderIds) {
        List<Id> ids = orderIds == null ? new List<Id>() : new List<Id>(orderIds);
        if (ids.size() > MAX_ORDERS_PER_BATCH) {
            throw new ActivationBatchException(
                'Activate at most ' +
                MAX_ORDERS_PER_BATCH +
                ' orders per batch. Split the request into smaller batches.'
            );
        }

        List<List<Id>> chunks = planChunks(ids);
        String correlationId = String.valueOf(UUID.randomUUID());
        DateTime startedAt = System.now();
        Id lastJobId = null;

        for (Integer index = 0; index < chunks.size(); index++) {
            lastJobId = System.enqueueJob(
                new ActivationBatchJob(
                    chunks[index],
                    correlationId,
                    index + 1,
                    chunks.size(),
                    ids.size(),
                    startedAt
                )
            );
        }

        return lastJobId;
    }

    @TestVisible
    static List<List<Id>> planChunks(List<Id> orderIds) {
        List<List<Id>> chunks = new List<List<Id>>();
        if (orderIds == null || orderIds.isEmpty()) {
            chunks.add(new List<Id>());
            return chunks;
        }

        for (
            Integer startIndex = 0;
            startIndex < orderIds.size();
            startIndex += ActivationService.MAX_ORDERS_PER_CALL
        ) {
            Integer endIndex = Math.min(
                startIndex + ActivationService.MAX_ORDERS_PER_CALL,
                orderIds.size()
            );
            List<Id> chunk = new List<Id>();
            for (Integer cursor = startIndex; cursor < endIndex; cursor++) {
                chunk.add(orderIds[cursor]);
            }
            chunks.add(chunk);
        }
        return chunks;
    }

    public void execute(QueueableContext context) {
        List<ActivationService.ActivationResult> results =
            ActivationService.activate(chunk, batchCorrelationId);

        Integer activatedCount = 0;
        Integer noOpCount = 0;
        Integer failedCount = 0;
        String firstFailureMessage;
        for (ActivationService.ActivationResult result : results) {
            if (result.status == 'Activated') {
                activatedCount++;
            } else if (result.status == 'NoOp') {
                noOpCount++;
            } else {
                failedCount++;
                if (String.isBlank(firstFailureMessage)) {
                    firstFailureMessage = result.message;
                }
            }
        }

        writeSummary(
            results.size(),
            activatedCount,
            noOpCount,
            failedCount,
            firstFailureMessage
        );
    }

    private void writeSummary(
        Integer processedCount,
        Integer activatedCount,
        Integer noOpCount,
        Integer failedCount,
        String firstFailureMessage
    ) {
        try {
            Integration_Log__c summary = new Integration_Log__c(
                Correlation_Id__c = batchCorrelationId,
                Direction__c = 'Outbound',
                System__c = 'Other',
                Operation__c = OPERATION,
                Status__c = failedCount > 0 ? 'Failure' : 'Success',
                Status_Code__c = failedCount > 0 ? '207' : '200',
                Duration_Ms__c = elapsedMs(),
                Endpoint__c = ENDPOINT,
                Payload_Summary__c = (
                    'Activation batch chunk ' +
                    chunkNumber +
                    '/' +
                    chunkCount +
                    ' processed ' +
                    processedCount +
                    ' of ' +
                    expectedCount +
                    ' order(s): ' +
                    activatedCount +
                    ' activated, ' +
                    noOpCount +
                    ' no-op, ' +
                    failedCount +
                    ' failed.'
                ).left(255),
                Error_Message__c = firstFailureMessage == null
                    ? null
                    : firstFailureMessage.left(255),
                Retry_Count__c = 0
            );
            Database.insert(summary, AccessLevel.USER_MODE);
        } catch (Exception ignored) {
            // The per-order logs are the primary audit trail; never mask them.
        }
    }

    private Integer elapsedMs() {
        if (startedAt == null) {
            return 0;
        }
        return (Integer) (System.now().getTime() - startedAt.getTime());
    }
}
