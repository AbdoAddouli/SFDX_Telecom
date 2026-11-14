@IsTest
private class ActivationPermissionSetTest {
    private static final String ADVISOR_PERMISSION_SET = 'ats_Advisor';
    private static final String MANAGER_PERMISSION_SET = 'ats_AdvisorManager';
    private static final String ADVISOR_USERNAME =
        'ats.permissions.advisor.' + UserInfo.getUserId() + '@example.com';
    private static final String MANAGER_USERNAME =
        'ats.permissions.manager.' + UserInfo.getUserId() + '@example.com';
    private static final String PRICEBOOK_NAME = 'Permission Test Pricebook';
    private static final String PRODUCT_CODE = 'PERM_FIBER';
    private static final String ACCOUNT_NAME = 'Permission Test Account';

    @TestSetup
    static void setupPersonas() {
        createPersonaUser(ADVISOR_PERMISSION_SET, ADVISOR_USERNAME, 'atsadv');
        createPersonaUser(MANAGER_PERMISSION_SET, MANAGER_USERNAME, 'atsmgr');
    }

    @IsTest
    static void advisorPersonaHasActivationCrudAndFls() {
        assertPersonaPermissions(ADVISOR_PERMISSION_SET);
    }

    @IsTest
    static void managerPersonaHasActivationCrudAndFls() {
        assertPersonaPermissions(MANAGER_PERMISSION_SET);
    }

    @IsTest
    static void advisorCanActivateOrderInUserMode() {
        runActivationAs(ADVISOR_USERNAME);
    }

    @IsTest
    static void managerCanActivateOrderInUserMode() {
        runActivationAs(MANAGER_USERNAME);
    }

    private static void assertPersonaPermissions(String permissionSetName) {
        PermissionSet permissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :permissionSetName
            LIMIT 1
        ];

        Map<String, ObjectPermissions> objects = new Map<String, ObjectPermissions>();
        for (ObjectPermissions permission : [
            SELECT SobjectType, PermissionsCreate, PermissionsRead,
                PermissionsEdit, PermissionsDelete
            FROM ObjectPermissions
            WHERE ParentId = :permissionSet.Id
        ]) {
            objects.put(permission.SobjectType, permission);
        }

        assertObject(objects, 'Order', true, true, true);
        // OrderItem permissions are inherited from Order in this org.
        assertObject(objects, 'Asset', true, false, true);
        assertObject(objects, 'Contract', true, true, true);
        assertObject(objects, 'Subscription__c', true, true, true);
        assertObject(
            objects,
            'Engagement__c',
            true,
            permissionSetName == MANAGER_PERMISSION_SET,
            true
        );
        assertObject(objects, 'Integration_Log__c', true, false, true);

        Set<String> editableFields = new Set<String>{
            'Subscription__c.Activation_Date__c',
            'Subscription__c.Billing_End_Date__c',
            'Subscription__c.Billing_Start_Date__c',
            'Subscription__c.Contact__c',
            'Subscription__c.Contract__c',
            'Subscription__c.Engagement__c',
            'Subscription__c.External_Reference__c',
            'Subscription__c.External_Status__c',
            'Subscription__c.Last_Sync_DateTime__c',
            'Subscription__c.Line_Number__c',
            'Subscription__c.MSISDN__c',
            'Subscription__c.Monthly_Amount__c',
            'Subscription__c.Order_Product__c',
            'Subscription__c.Parent_Subscription__c',
            'Subscription__c.Product__c',
            'Subscription__c.Root_Engagement__c',
            'Engagement__c.Asset__c',
            'Engagement__c.Contract__c',
            'Engagement__c.Engagement_Key__c',
            'Engagement__c.Monthly_Amount__c',
            'Engagement__c.Penalty_Rate__c',
            'Engagement__c.Penalty_Rule__c',
            'Order.Activated_By__c',
            'Order.Activated_On__c',
            'Order.Activation_State__c',
            'Order.BSS_Order_Key__c',
            'Order.Failure_Reason__c',
            'OrderItem.Creates_Asset__c',
            'OrderItem.Subscription_Number__c',
            'OrderItem.Commitment_Option_Code__c',
            'Asset.Is_Primary__c',
            'Asset.Provisioned_Status__c',
            'Asset.Service_Line_Type__c',
            'Contract.ATS_Contract_Type__c',
            'Contract.Auto_Renew__c',
            'Contract.Signed_On__c',
            'Integration_Log__c.Duration_Ms__c',
            'Integration_Log__c.Endpoint__c',
            'Integration_Log__c.Error_Message__c',
            'Integration_Log__c.Idempotency_Key__c',
            'Integration_Log__c.Order__c',
            'Integration_Log__c.Payload_Summary__c',
            'Integration_Log__c.Retry_Count__c',
            'Integration_Log__c.Status_Code__c',
            'Integration_Log__c.Subscription__c'
        };

        Set<String> actualEditableFields = new Set<String>();
        for (FieldPermissions permission : [
            SELECT Field, PermissionsRead, PermissionsEdit
            FROM FieldPermissions
            WHERE ParentId = :permissionSet.Id
        ]) {
            if (permission.PermissionsRead && permission.PermissionsEdit) {
                actualEditableFields.add(permission.Field);
            }
        }

        for (String field : editableFields) {
            System.assert(
                actualEditableFields.contains(field),
                permissionSetName + ' must grant editable access to ' + field
            );
        }

        List<SetupEntityAccess> classAccess = [
            SELECT Id
            FROM SetupEntityAccess
            WHERE ParentId = :permissionSet.Id
                AND SetupEntityId IN (
                    SELECT Id FROM ApexClass WHERE Name = 'ActivationService'
                )
        ];
        System.assertEquals(
            1,
            classAccess.size(),
            permissionSetName + ' must grant ActivationService class access'
        );
    }

    private static void assertObject(
        Map<String, ObjectPermissions> objects,
        String objectName,
        Boolean create,
        Boolean edit,
        Boolean read
    ) {
        ObjectPermissions permission = objects.get(objectName);
        System.assertNotEquals(null, permission, 'Missing ' + objectName);
        System.assertEquals(create, permission.PermissionsCreate, objectName);
        System.assertEquals(read, permission.PermissionsRead, objectName);
        System.assertEquals(edit, permission.PermissionsEdit, objectName);
        System.assertEquals(
            false,
            permission.PermissionsDelete,
            objectName + ' must not be deletable'
        );
    }

    private static void runActivationAs(String username) {
        User persona = [SELECT Id FROM User WHERE Username = :username LIMIT 1];
        ATS_Feature_Flags__c flags = ATS_Feature_Flags__c.getOrgDefaults();
        if (flags == null || flags.Id == null) {
            insert new ATS_Feature_Flags__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                BSS_Provisioning_Enabled__c = true
            );
        } else {
            flags.BSS_Provisioning_Enabled__c = true;
            update flags;
        }

        Pricebook2 pricebook = new Pricebook2(
            Name = PRICEBOOK_NAME,
            IsActive = true
        );
        insert pricebook;

        Product2 product = new Product2(
            Name = 'Permission Fiber 100',
            Family = 'TELCO_FIBER',
            Plan_Type__c = 'Fiber',
            Recurring__c = true,
            Requires_Commitment__c = true,
            IsActive = true,
            Is_Active__c = true,
            ATS_Product_Code__c = PRODUCT_CODE
        );
        insert product;

        insert new List<PricebookEntry>{
            new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id = product.Id,
                UnitPrice = 39.99,
                IsActive = true,
                UseStandardPrice = false
            ),
            new PricebookEntry(
                Pricebook2Id = pricebook.Id,
                Product2Id = product.Id,
                UnitPrice = 39.99,
                IsActive = true,
                UseStandardPrice = false
            )
        };

        PricebookEntry entry = [
            SELECT Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebook.Id
                AND Product2Id = :product.Id
            LIMIT 1
        ];
        Account account = new Account(
            Name = ACCOUNT_NAME,
            Segment__c = 'Consumer',
            OwnerId = persona.Id
        );
        insert account;
        Contact contact = new Contact(
            LastName = 'Permission Contact',
            AccountId = account.Id,
            OwnerId = persona.Id
        );
        insert contact;

        Order order = new Order(
            Name = 'Permission Test Order',
            AccountId = account.Id,
            BillToContactId = contact.Id,
            Pricebook2Id = pricebook.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Activation_State__c = 'Ready',
            OwnerId = persona.Id
        );
        insert order;
        insert new OrderItem(
            OrderId = order.Id,
            PricebookEntryId = entry.Id,
            Product2Id = product.Id,
            Quantity = 1,
            UnitPrice = entry.UnitPrice,
            ServiceDate = Date.today(),
            Description = product.Name,
            Commitment_Option_Code__c = 'COMMIT12'
        );

        ActivationService.ActivationResult result;
        Test.startTest();
        System.runAs(persona) {
            result = ActivationService.activateOrder(order.Id);
        }
        Test.stopTest();

        System.assertEquals('Activated', result.status, result.message);
        System.assertEquals(1, result.assetCount);
        System.assertEquals(1, result.subscriptionCount);
        System.assertEquals(1, result.engagementCount);

        Order activated = [
            SELECT Status, Activation_State__c, ContractId
            FROM Order
            WHERE Id = :order.Id
        ];
        System.assertEquals('Activated', activated.Status);
        System.assertEquals('Activated', activated.Activation_State__c);
        System.assertNotEquals(null, activated.ContractId);

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Subscription__c WHERE Account__c = :account.Id]
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Engagement__c WHERE Account__c = :account.Id]
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Integration_Log__c WHERE Order__c = :order.Id]
        );
    }

    private static void createPersonaUser(
        String permissionSetName,
        String username,
        String alias
    ) {
        Profile personaProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        User persona = new User(
            Alias = alias,
            Email = username,
            EmailEncodingKey = 'UTF-8',
            FirstName = 'Permission',
            LastName = 'Tester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = personaProfile.Id,
            TimeZoneSidKey = 'Europe/Paris',
            UserName = username
        );
        insert persona;

        PermissionSet permissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :permissionSetName
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = persona.Id,
            PermissionSetId = permissionSet.Id
        );
    }
}
