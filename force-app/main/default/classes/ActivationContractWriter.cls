/**
 * Isolates contract binding behind one class. The current default is AMEND:
 * reuse the Order's contract and activate it. A later Q1 decision to create a
 * new contract is a contained change here rather than in ActivationService.
 */
public with sharing class ActivationContractWriter {
    public class ContractException extends Exception {
    }

    public static Contract ensure(
        Order order,
        Integer maxTerm,
        String contractType
    ) {
        if (order.ContractId != null) {
            List<Contract> contracts = [
                SELECT
                    Id,
                    AccountId,
                    StartDate,
                    Status,
                    ContractTerm,
                    Signed_On__c,
                    ATS_Contract_Type__c,
                    Auto_Renew__c,
                    Pricebook2Id,
                    Description
                FROM Contract
                WHERE Id = :order.ContractId
                WITH USER_MODE
            ];
            if (contracts.isEmpty()) {
                throw new ContractException(
                    'The contract linked to this order no longer exists.'
                );
            }

            Contract existing = contracts[0];
            Boolean dirty = false;
            if (existing.StartDate == null) {
                existing.StartDate = Date.today();
                dirty = true;
            }
            if (existing.Signed_On__c == null) {
                existing.Signed_On__c = Date.today();
                dirty = true;
            }
            if (existing.ContractTerm == null && maxTerm > 0) {
                existing.ContractTerm = maxTerm;
                dirty = true;
            }
            if (String.isBlank(existing.ATS_Contract_Type__c)) {
                existing.ATS_Contract_Type__c = contractType;
                dirty = true;
            }
            if (
                existing.Pricebook2Id == null &&
                order.Pricebook2Id != null
            ) {
                existing.Pricebook2Id = order.Pricebook2Id;
                dirty = true;
            }
            if (dirty) {
                Database.update(existing, AccessLevel.USER_MODE);
            }
            return existing;
        }

        Contract created = new Contract(
            AccountId = order.AccountId,
            StartDate = Date.today(),
            Status = 'Draft',
            ContractTerm = maxTerm > 0 ? maxTerm : null,
            Signed_On__c = Date.today(),
            ATS_Contract_Type__c = contractType,
            Auto_Renew__c = false,
            Pricebook2Id = order.Pricebook2Id,
            Description = ('ATS activation for order ' + order.OrderNumber)
                .left(32000)
        );
        Database.insert(created, AccessLevel.USER_MODE);
        return created;
    }

    public static void activate(Contract contract) {
        if (contract.Status == 'Activated') {
            return;
        }
        Contract activation = new Contract(Id = contract.Id, Status = 'Activated');
        if (contract.StartDate == null) {
            activation.StartDate = Date.today();
        }
        Database.update(activation, AccessLevel.USER_MODE);
    }
}
