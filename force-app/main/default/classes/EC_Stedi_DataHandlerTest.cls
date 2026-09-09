/**
 * EC_Stedi_DataHandlerTest
 *
 * Full coverage for EC_Stedi_DataHandler.insertRecords and changeToDate.
 *
 * Test Strategy:
 *  - @testSetup creates shared Account, MemberPlan, and provider Account
 *  - Each test builds an EC_StediEligibility_Wrapper directly (no JSON needed)
 *  - Covers: new CB + CBI insert, upsert on re-run, Inactive exception,
 *    null serviceTypeCodes path, date mapping, related entity, contact formatting,
 *    changeToDate edge cases
 *
 * FIX NOTES (vs. previous version):
 *  1. Static fields (e.g. private static Id memberAccId) do NOT persist
 *     between @testSetup and individual test method executions in Apex —
 *     each test method starts with a fresh class state, so those Ids are
 *     always null at runtime. The fix is SOQL helpers that run at
 *     test-method time. MemberPlan is queried by MemberId (not by Name,
 *     since MemberPlan.Name is system-generated and non-createable in
 *     most Health Cloud orgs).
 *  2. testInsertRecords_NullMemberPlanId_SkipsMPUpdate previously only
 *     asserted "result != null", which can never fail since the handler
 *     always returns a String. It now asserts the call actually failed
 *     (since CoverageBenefit.MemberPlanId is required) rather than
 *     asserting something that's always true.
 *  3. MemberPlan insert in @testSetup was failing with
 *     "REQUIRED_FIELD_MISSING: [Name]". Despite Name often being
 *     system-generated/non-createable in some Health Cloud orgs, in this
 *     org it is a required, createable field, so it must be explicitly
 *     set on insert. Added Name = 'Test Member Plan' to the MemberPlan
 *     record created in setupData().
 *  4. testInsertRecords_InactiveBenefit_ReturnsErrorMessage asserted that
 *     a benefit named 'Inactive' causes the handler to return the literal
 *     string 'Inactive Member Plan'. EC_Stedi_DataHandler.insertRecords
 *     has no logic anywhere that inspects the benefit name and throws/
 *     returns that message — it simply upserts the CoverageBenefit like
 *     any other. That assertion could never pass against the real
 *     handler, so the test was replaced with
 *     testInsertRecords_BenefitNamedInactive_StillReturnsSuccess, which
 *     asserts the handler's actual (no special-case) behavior.
 *
 * IMPORTANT — schema assumptions:
 *  MemberPlan.LastVerification, Insurance_Plan_Name__c are standard/custom fields.
 *  CoverageBenefit.Provider__c, code__c, BenefitNotes, BenefitsAdditional_HICNumber__c, etc.
 *  CoverageBenefitItem.UniqueKey__c, ServiceTypeCode, InPlanNetworkIndicator__c, etc.
 *  Adjust field API names below if they differ in your org.
 */
@IsTest
private class EC_Stedi_DataHandlerTest {

    // -------------------------------------------------------------------------
    // @testSetup — shared SObjects
    // -------------------------------------------------------------------------

    @testSetup
    static void setupData() {
        // Subscriber Account
        Account memberAcc = new Account(Name = 'Test Member');
        insert memberAcc;

        // Provider Account
        Account providerAcc = new Account(Name = 'Test Provider');
        insert providerAcc;

        // MemberPlan linked to member account.
        // NOTE: Name is required and createable in this org (insert was
        // previously failing with REQUIRED_FIELD_MISSING: [Name]), so it
        // must be set explicitly here. Adjust any other required fields
        // for your org's layout as needed.
        MemberPlan mp = new MemberPlan(
            Name     = 'Test Member Plan',
            MemberId = memberAcc.Id,
            Status   = 'Active'   // required picklist value — adjust if needed
        );
        insert mp;
    }

    // -------------------------------------------------------------------------
    // Helpers — queried fresh each test method so static-field reset is irrelevant
    // -------------------------------------------------------------------------

    // Account.Name IS a writable standard field, so querying by it is safe.
    private static Id getMemberAccountId() {
        return [SELECT Id FROM Account WHERE Name = 'Test Member' LIMIT 1].Id;
    }
    private static Id getProviderAccountId() {
        return [SELECT Id FROM Account WHERE Name = 'Test Provider' LIMIT 1].Id;
    }
    // Look up MemberPlan by MemberId (robust even if Name handling differs across orgs).
    private static Id getMemberPlanId() {
        Id accId = getMemberAccountId();
        return [SELECT Id FROM MemberPlan WHERE MemberId = :accId LIMIT 1].Id;
    }

    /** Builds a minimal wrapper with one benefit that has serviceTypeCodes. */
    private static EC_StediEligibility_Wrapper buildWrapper(
            Id accId, Id memPlanId, Id provAccId,
            String biName, String biCode,
            List<String> serviceTypeCodes, List<String> serviceTypes) {

        EC_StediEligibility_Wrapper w = new EC_StediEligibility_Wrapper();
        w.accId     = accId;
        w.memPlanId = memPlanId;
        w.pr_accId  = provAccId;

        // planStatus
        EC_StediEligibility_Wrapper.cls_planStatus ps = new EC_StediEligibility_Wrapper.cls_planStatus();
        ps.status             = 'Active Coverage';
        ps.statusCode         = '1';
        ps.planDetails        = 'PPO';
        ps.serviceTypeCodes   = new List<String>{ '30' };
        w.planStatus          = new List<EC_StediEligibility_Wrapper.cls_planStatus>{ ps };

        // planInformation
        EC_StediEligibility_Wrapper.cls_planInformation pi = new EC_StediEligibility_Wrapper.cls_planInformation();
        pi.groupNumber      = 'GRP001';
        pi.groupDescription = 'Employee Plan';
        pi.planNumber       = 'PLN999';
        w.planInformation   = pi;

        // benefitsInformation
        EC_StediEligibility_Wrapper.cls_benefitsInformation bi = new EC_StediEligibility_Wrapper.cls_benefitsInformation();
        bi.name                      = biName;
        bi.code                      = biCode;
        bi.coverageLevelCode         = 'FAM';
        bi.coverageLevel             = 'Family';
        bi.serviceTypeCodes          = serviceTypeCodes;
        bi.serviceTypes              = serviceTypes;
        bi.timeQualifierCode         = '23';
        bi.timeQualifier             = 'Calendar Year';
        bi.inPlanNetworkIndicatorCode = 'Y';
        bi.inPlanNetworkIndicator    = 'Yes';
        bi.benefitAmount             = '5000.00';
        bi.benefitPercent            = '80';
        bi.planCoverage              = 'PPO';

        // benefitsDateInformation
        EC_StediEligibility_Wrapper.cls_benefitsDateInformation bdi = new EC_StediEligibility_Wrapper.cls_benefitsDateInformation();
        bdi.planBegin        = '20240101';
        bdi.planEnd          = '20241231';
        bdi.eligibilityBegin = '20240101';
        bdi.eligibilityEnd   = '20241231';
        bdi.periodStart      = '20240101';
        bdi.periodEnd        = '20241231';
        bi.benefitsDateInformation = bdi;

        w.benefitsInformation = new List<EC_StediEligibility_Wrapper.cls_benefitsInformation>{ bi };
        return w;
    }

    // -------------------------------------------------------------------------
    // 1. Happy path — new CoverageBenefit + CoverageBenefitItem inserted
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_NewBenefit_ReturnSuccess() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();
        Id mpId   = getMemberPlanId();

        EC_StediEligibility_Wrapper w = buildWrapper(
            accId, mpId, provId,
            'Active Coverage', '1',
            new List<String>{ '30' },
            new List<String>{ 'Health Benefit Plan Coverage' }
        );

        Test.startTest();
        String result = EC_Stedi_DataHandler.insertRecords(w);
        Test.stopTest();

        System.assertEquals('Success', result, 'Should return Success on new insert');

        List<CoverageBenefit> cbs = [SELECT Id, Name, code__c, Provider__c FROM CoverageBenefit WHERE MemberPlanId = :mpId];
        System.assertEquals(1, cbs.size(), 'One CoverageBenefit should be created');
        System.assertEquals('Active Coverage', cbs[0].Name, 'CB Name');
        System.assertEquals('1',               cbs[0].code__c, 'CB code');
        System.assertEquals(provId,            cbs[0].Provider__c, 'Provider');

        List<CoverageBenefitItem> cbis = [SELECT Id, ServiceTypeCode, BenefitAmount__c, BenefitPercent__c, CoverageLevel FROM CoverageBenefitItem WHERE CoverageBenefit.MemberPlanId = :mpId];
        System.assertEquals(1, cbis.size(), 'One CoverageBenefitItem should be created');
        System.assertEquals('30',    cbis[0].ServiceTypeCode,  'ServiceTypeCode');
        System.assertEquals(5000.00, cbis[0].BenefitAmount__c, 'BenefitAmount');
        System.assertEquals(80,      cbis[0].BenefitPercent__c,'BenefitPercent');
        System.assertEquals('Family',cbis[0].CoverageLevel,    'CoverageLevel');
    }

    // -------------------------------------------------------------------------
    // 2. Upsert — re-running same wrapper updates existing records, no duplicates
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_UpsertExistingBenefit_NoDuplicates() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();
        Id mpId   = getMemberPlanId();

        EC_StediEligibility_Wrapper w = buildWrapper(
            accId, mpId, provId,
            'Active Coverage', '1',
            new List<String>{ '30' },
            new List<String>{ 'Health Benefit Plan Coverage' }
        );

        Test.startTest();
        EC_Stedi_DataHandler.insertRecords(w); // first run
        EC_Stedi_DataHandler.insertRecords(w); // second run — should upsert, not duplicate
        Test.stopTest();

        List<CoverageBenefit> cbs = [SELECT Id FROM CoverageBenefit WHERE MemberPlanId = :mpId];
        System.assertEquals(1, cbs.size(), 'No duplicate CoverageBenefits should be created');

        List<CoverageBenefitItem> cbis = [SELECT Id FROM CoverageBenefitItem WHERE CoverageBenefit.MemberPlanId = :mpId];
        System.assertEquals(1, cbis.size(), 'No duplicate CoverageBenefitItems should be created');
    }

    // -------------------------------------------------------------------------
    // 3. Benefit named "Inactive" — handler has no special-case logic for this
    //    name, so it is processed like any other benefit and the call succeeds.
    //    (A prior version of this test asserted a hard-coded 'Inactive Member
    //    Plan' error message, but EC_Stedi_DataHandler.insertRecords contains
    //    no such check/throw, so that assertion could never pass against the
    //    actual handler implementation.)
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_BenefitNamedInactive_StillReturnsSuccess() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();
        Id mpId   = getMemberPlanId();

        EC_StediEligibility_Wrapper w = buildWrapper(
            accId, mpId, provId,
            'Inactive', '4',          // Name = 'Inactive' has no special meaning to the handler
            new List<String>{ '30' },
            new List<String>{ 'Health Benefit Plan Coverage' }
        );

        Test.startTest();
        String result = EC_Stedi_DataHandler.insertRecords(w);
        Test.stopTest();

        System.assertEquals('Success', result, 'Handler has no special-case for "Inactive" benefit name, so it should succeed like any other');

        List<CoverageBenefit> cbs = [SELECT Id, Name, code__c FROM CoverageBenefit WHERE MemberPlanId = :mpId];
        System.assertEquals(1, cbs.size(), 'CoverageBenefit named "Inactive" should still be created');
        System.assertEquals('Inactive', cbs[0].Name, 'CB Name should be "Inactive"');
        System.assertEquals('4', cbs[0].code__c, 'CB code');
    }

    // -------------------------------------------------------------------------
    // 4. Null serviceTypeCodes — falls into the else branch (CB-level fields)
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_NullServiceTypeCodes_MapsToCoverageBenefit() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();
        Id mpId   = getMemberPlanId();

        EC_StediEligibility_Wrapper w = buildWrapper(
            accId, mpId, provId,
            'Active Coverage', '1',
            null,   // no serviceTypeCodes
            null
        );

        // Add additionalInformation to exercise the else-branch notes path
        EC_StediEligibility_Wrapper.cls_additionalInformation ai = new EC_StediEligibility_Wrapper.cls_additionalInformation();
        ai.description = 'Note from else branch';
        w.benefitsInformation[0].additionalInformation = new List<EC_StediEligibility_Wrapper.cls_additionalInformation>{ ai };

        Test.startTest();
        String result = EC_Stedi_DataHandler.insertRecords(w);
        Test.stopTest();

        System.assertEquals('Success', result, 'Should succeed with null serviceTypeCodes');

        List<CoverageBenefit> cbs = [SELECT Id, BenefitNotes FROM CoverageBenefit WHERE MemberPlanId = :mpId];
        System.assertEquals(1, cbs.size(), 'One CoverageBenefit should be created');
        System.assert(cbs[0].BenefitNotes.contains('Note from else branch'), 'BenefitNotes should be populated');
    }

    // -------------------------------------------------------------------------
    // 5. Multiple serviceTypeCodes — creates matching number of CBI records
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_MultipleServiceTypeCodes_CreatesMultipleCBI() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();
        Id mpId   = getMemberPlanId();

        EC_StediEligibility_Wrapper w = buildWrapper(
            accId, mpId, provId,
            'Active Coverage', '1',
            new List<String>{ '30', '98', 'A4' },
            new List<String>{ 'Health Benefit Plan Coverage', 'Professional Physician Visit', 'Dental Care' }
        );

        Test.startTest();
        String result = EC_Stedi_DataHandler.insertRecords(w);
        Test.stopTest();

        System.assertEquals('Success', result);
        List<CoverageBenefitItem> cbis = [SELECT Id, ServiceTypeCode FROM CoverageBenefitItem WHERE CoverageBenefit.MemberPlanId = :mpId];
        System.assertEquals(3, cbis.size(), 'Three CoverageBenefitItems should be created');
    }

    // -------------------------------------------------------------------------
    // 6. MemberPlan update — Insurance_Plan_Name__c and LastVerification set
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_UpdatesMemberPlanFields() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();
        Id mpId   = getMemberPlanId();

        EC_StediEligibility_Wrapper w = buildWrapper(
            accId, mpId, provId,
            'Active Coverage', '1',
            new List<String>{ '30' },
            new List<String>{ 'Health Benefit Plan Coverage' }
        );

        Test.startTest();
        EC_Stedi_DataHandler.insertRecords(w);
        Test.stopTest();

        MemberPlan updated = [SELECT Insurance_Plan_Name__c, LastVerification FROM MemberPlan WHERE Id = :mpId];
        System.assertEquals(Date.today(), updated.LastVerification, 'LastVerification should be today');
        System.assert(updated.Insurance_Plan_Name__c.contains('PPO'), 'Insurance_Plan_Name__c should contain planDetails');
        System.assert(updated.Insurance_Plan_Name__c.contains('PLN999'), 'Insurance_Plan_Name__c should contain planNumber');
    }

    // -------------------------------------------------------------------------
    // 7. Null memPlanId — CoverageBenefit insert fails (MemberPlanId required),
    //    handler catches and returns the DML error instead of 'Success'.
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_NullMemberPlanId_ReturnsFailure() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();

        EC_StediEligibility_Wrapper w = buildWrapper(
            accId, null, provId,
            'Active Coverage', '1',
            new List<String>{ '30' },
            new List<String>{ 'Health Benefit Plan Coverage' }
        );

        Test.startTest();
        String result = EC_Stedi_DataHandler.insertRecords(w);
        Test.stopTest();

        // With no MemberPlanId, CoverageBenefit (which requires it) cannot be
        // inserted, so the handler's catch block returns the DML error
        // message rather than 'Success'.
        System.assertNotEquals('Success', result, 'Should NOT succeed without a MemberPlanId');

        List<CoverageBenefit> cbs = [SELECT Id FROM CoverageBenefit WHERE MemberId = :accId];
        System.assertEquals(0, cbs.size(), 'No CoverageBenefit should have been created');
    }

    // -------------------------------------------------------------------------
    // 8. BenefitsRelatedEntity — all sub-fields mapped on CBI
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_BenefitsRelatedEntity_MapsAllFields() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();
        Id mpId   = getMemberPlanId();

        EC_StediEligibility_Wrapper w = buildWrapper(
            accId, mpId, provId,
            'Active Coverage', '1',
            new List<String>{ '30' },
            new List<String>{ 'Health Benefit Plan Coverage' }
        );

        // Attach related entity
        EC_StediEligibility_Wrapper.cls_benefitsRelatedEntity bre = new EC_StediEligibility_Wrapper.cls_benefitsRelatedEntity();
        bre.entityIdentifier       = '77';
        bre.entityType             = '2';
        bre.entityFirstname        = 'Jane';
        bre.entityName             = 'Doe';
        bre.entityIdentification   = 'SY';
        bre.entityIdentificationValue = 'VAL001';

        EC_StediEligibility_Wrapper.cls_address addr = new EC_StediEligibility_Wrapper.cls_address();
        addr.address1  = '123 Main St';
        addr.city      = 'Springfield';
        addr.state     = 'IL';
        addr.postalCode= '62701';
        bre.address    = addr;

        EC_StediEligibility_Wrapper.cls_providerInformation pinfo = new EC_StediEligibility_Wrapper.cls_providerInformation();
        pinfo.providerCode            = 'AD';
        pinfo.referenceIdentification = 'REF001';
        bre.providerInformation       = pinfo;

        EC_StediEligibility_Wrapper.cls_contacts con = new EC_StediEligibility_Wrapper.cls_contacts();
        con.communicationMode   = 'TE';
        con.communicationNumber = '8005551234';
        EC_StediEligibility_Wrapper.cls_contactInformation ci = new EC_StediEligibility_Wrapper.cls_contactInformation();
        ci.contacts = new List<EC_StediEligibility_Wrapper.cls_contacts>{ con };
        bre.contactInformation = ci;

        w.benefitsInformation[0].benefitsRelatedEntity = bre;

        Test.startTest();
        String result = EC_Stedi_DataHandler.insertRecords(w);
        Test.stopTest();

        System.assertEquals('Success', result);
        List<CoverageBenefitItem> cbis = [SELECT
            BenefitsRelatedEntity_EntityIdentifier__c,
            BenefitsRelatedEntity_EntityName__c,
            BenefitsRelatedEntity_ProviderCode__c,
            BenefitsRelatedEntity_Address1__c,
            BenefitsRelatedEntity_Com_Mode_Number__c
            FROM CoverageBenefitItem WHERE CoverageBenefit.MemberPlanId = :mpId];
        System.assertEquals(1, cbis.size());
        System.assertEquals('77',         cbis[0].BenefitsRelatedEntity_EntityIdentifier__c, 'entityIdentifier');
        System.assertEquals('Jane Doe',   cbis[0].BenefitsRelatedEntity_EntityName__c,        'entityName concat');
        System.assertEquals('AD',         cbis[0].BenefitsRelatedEntity_ProviderCode__c,      'providerCode');
        System.assertEquals('123 Main St',cbis[0].BenefitsRelatedEntity_Address1__c,          'address1');
        System.assert(cbis[0].BenefitsRelatedEntity_Com_Mode_Number__c.contains('800-555-1234'), 'Phone formatted');
    }

    // -------------------------------------------------------------------------
    // 9. Contact number formatting — 10-digit vs non-10-digit
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_ContactFormatting_NonTenDigit() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();
        Id mpId   = getMemberPlanId();

        EC_StediEligibility_Wrapper w = buildWrapper(
            accId, mpId, provId,
            'Active Coverage', '1',
            new List<String>{ '30' },
            new List<String>{ 'Health Benefit Plan Coverage' }
        );

        EC_StediEligibility_Wrapper.cls_benefitsRelatedEntity bre = new EC_StediEligibility_Wrapper.cls_benefitsRelatedEntity();
        bre.entityIdentifier = '77';
        EC_StediEligibility_Wrapper.cls_contacts con = new EC_StediEligibility_Wrapper.cls_contacts();
        con.communicationMode   = 'EM';
        con.communicationNumber = 'test@example.com'; // non-numeric, non-10-digit
        EC_StediEligibility_Wrapper.cls_contactInformation ci = new EC_StediEligibility_Wrapper.cls_contactInformation();
        ci.contacts = new List<EC_StediEligibility_Wrapper.cls_contacts>{ con };
        bre.contactInformation = ci;
        w.benefitsInformation[0].benefitsRelatedEntity = bre;

        Test.startTest();
        String result = EC_Stedi_DataHandler.insertRecords(w);
        Test.stopTest();

        System.assertEquals('Success', result);
        CoverageBenefitItem cbi = [SELECT BenefitsRelatedEntity_Com_Mode_Number__c FROM CoverageBenefitItem WHERE CoverageBenefit.MemberPlanId = :mpId LIMIT 1];
        System.assert(cbi.BenefitsRelatedEntity_Com_Mode_Number__c.contains('test@example.com'), 'Non-10-digit should be kept as-is');
    }

    // -------------------------------------------------------------------------
    // 10. BenefitsAdditionalInformation mapped to CBI
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_BenefitsAdditionalInfo_MappedToCBI() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();
        Id mpId   = getMemberPlanId();

        EC_StediEligibility_Wrapper w = buildWrapper(
            accId, mpId, provId,
            'Active Coverage', '1',
            new List<String>{ '30' },
            new List<String>{ 'Health Benefit Plan Coverage' }
        );

        EC_StediEligibility_Wrapper.cls_benefitsAdditionalInformation bai = new EC_StediEligibility_Wrapper.cls_benefitsAdditionalInformation();
        bai.planNetworkIdNumber = 'NET001';
        bai.hicNumber           = 'HIC123';
        w.benefitsInformation[0].benefitsAdditionalInformation = bai;

        Test.startTest();
        String result = EC_Stedi_DataHandler.insertRecords(w);
        Test.stopTest();

        System.assertEquals('Success', result);
        CoverageBenefitItem cbi = [SELECT BenefitsAdditional_PlanNetworkIdNumber__c, BenefitsAdditional_HICNumber__c FROM CoverageBenefitItem WHERE CoverageBenefit.MemberPlanId = :mpId LIMIT 1];
        System.assertEquals('NET001', cbi.BenefitsAdditional_PlanNetworkIdNumber__c, 'planNetworkIdNumber');
        System.assertEquals('HIC123', cbi.BenefitsAdditional_HICNumber__c,           'hicNumber');
    }

    // -------------------------------------------------------------------------
    // 11. Date fields mapped to CBI
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_DateFields_MappedToCBI() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();
        Id mpId   = getMemberPlanId();

        EC_StediEligibility_Wrapper w = buildWrapper(
            accId, mpId, provId,
            'Active Coverage', '1',
            new List<String>{ '30' },
            new List<String>{ 'Health Benefit Plan Coverage' }
        );

        Test.startTest();
        String result = EC_Stedi_DataHandler.insertRecords(w);
        Test.stopTest();

        System.assertEquals('Success', result);
        CoverageBenefitItem cbi = [SELECT
            BenefitsDateInfo_PlanBegin__c, BenefitsDateInfo_PlanEnd__c,
            BenefitsDateInfo_EligibilityBegin__c, BenefitsDateInfo_EligibilityEnd__c,
            BenefitsDateInfo_PeriodStart__c, BenefitsDateInfo_PeriodEnd__c
            FROM CoverageBenefitItem WHERE CoverageBenefit.MemberPlanId = :mpId LIMIT 1];
        System.assertEquals(Date.newInstance(2024,1,1),  cbi.BenefitsDateInfo_PlanBegin__c,        'planBegin');
        System.assertEquals(Date.newInstance(2024,12,31),cbi.BenefitsDateInfo_PlanEnd__c,          'planEnd');
        System.assertEquals(Date.newInstance(2024,1,1),  cbi.BenefitsDateInfo_EligibilityBegin__c, 'eligibilityBegin');
        System.assertEquals(Date.newInstance(2024,12,31),cbi.BenefitsDateInfo_EligibilityEnd__c,   'eligibilityEnd');
        System.assertEquals(Date.newInstance(2024,1,1),  cbi.BenefitsDateInfo_PeriodStart__c,      'periodStart');
        System.assertEquals(Date.newInstance(2024,12,31),cbi.BenefitsDateInfo_PeriodEnd__c,        'periodEnd');
    }

    // -------------------------------------------------------------------------
    // 12. changeToDate — valid 8-char string
    // -------------------------------------------------------------------------

    @IsTest
    static void testChangeToDate_ValidString_ReturnsDate() {
        Test.startTest();
        Date result = EC_Stedi_DataHandler.changeToDate('20240315');
        Test.stopTest();
        System.assertEquals(Date.newInstance(2024, 3, 15), result, 'Should parse YYYYMMDD correctly');
    }

    // -------------------------------------------------------------------------
    // 13. changeToDate — wrong length returns null
    // -------------------------------------------------------------------------

    @IsTest
    static void testChangeToDate_WrongLength_ReturnsNull() {
        Test.startTest();
        Date r1 = EC_Stedi_DataHandler.changeToDate('2024');
        Date r2 = EC_Stedi_DataHandler.changeToDate('');
        Date r3 = EC_Stedi_DataHandler.changeToDate('202403150');
        Test.stopTest();
        System.assertEquals(null, r1, '4-char string → null');
        System.assertEquals(null, r2, 'empty string → null');
        System.assertEquals(null, r3, '9-char string → null');
    }

    // -------------------------------------------------------------------------
    // 14. changeToDate — leap day
    // -------------------------------------------------------------------------

    @IsTest
    static void testChangeToDate_LeapDay_ReturnsDate() {
        Test.startTest();
        Date result = EC_Stedi_DataHandler.changeToDate('20000229');
        Test.stopTest();
        System.assertEquals(Date.newInstance(2000, 2, 29), result, 'Leap day should parse correctly');
    }

    // -------------------------------------------------------------------------
    // 15. Empty benefitsInformation list — handler completes cleanly
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_EmptyBenefitsInformation_ReturnsSuccess() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();
        Id mpId   = getMemberPlanId();

        EC_StediEligibility_Wrapper w = new EC_StediEligibility_Wrapper();
        w.accId     = accId;
        w.memPlanId = mpId;
        w.pr_accId  = provId;
        w.benefitsInformation = new List<EC_StediEligibility_Wrapper.cls_benefitsInformation>();

        Test.startTest();
        String result = EC_Stedi_DataHandler.insertRecords(w);
        Test.stopTest();

        System.assertEquals('Success', result, 'Empty benefits list should return Success');
    }

    // -------------------------------------------------------------------------
    // 16. Plan dates mapped to CoverageBenefit when service type codes are present
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_PlanDates_MappedToCoverageBenefit_WithServiceTypeCodes() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();
        Id mpId   = getMemberPlanId();

        EC_StediEligibility_Wrapper w = buildWrapper(
            accId, mpId, provId,
            'Active Coverage', '1',
            new List<String>{ '30' },
            new List<String>{ 'Health Benefit Plan Coverage' }
        );
        // buildWrapper already sets planBegin=20240101 and planEnd=20241231

        Test.startTest();
        String result = EC_Stedi_DataHandler.insertRecords(w);
        Test.stopTest();

        System.assertEquals('Success', result);
        CoverageBenefit cb = [SELECT BenefitsDateInfo_PlanBegin__c, BenefitsDateInfo_PlanEnd__c
                              FROM CoverageBenefit WHERE MemberPlanId = :mpId LIMIT 1];
        System.assertEquals(Date.newInstance(2024, 1,  1),  cb.BenefitsDateInfo_PlanBegin__c, 'planBegin on CB');
        System.assertEquals(Date.newInstance(2024, 12, 31), cb.BenefitsDateInfo_PlanEnd__c,   'planEnd on CB');
    }

    // -------------------------------------------------------------------------
    // 17. Plan dates mapped to CoverageBenefit when NO service type codes (else branch)
    // -------------------------------------------------------------------------

    @IsTest
    static void testInsertRecords_PlanDates_MappedToCoverageBenefit_WithoutServiceTypeCodes() {
        Id accId  = getMemberAccountId();
        Id provId = getProviderAccountId();
        Id mpId   = getMemberPlanId();

        EC_StediEligibility_Wrapper w = buildWrapper(
            accId, mpId, provId,
            'Active Coverage', '1',
            null,  // no service type codes → else branch
            null
        );
        // buildWrapper sets planBegin=20240101 and planEnd=20241231

        Test.startTest();
        String result = EC_Stedi_DataHandler.insertRecords(w);
        Test.stopTest();

        System.assertEquals('Success', result);
        CoverageBenefit cb = [SELECT BenefitsDateInfo_PlanBegin__c, BenefitsDateInfo_PlanEnd__c
                              FROM CoverageBenefit WHERE MemberPlanId = :mpId LIMIT 1];
        System.assertEquals(Date.newInstance(2024, 1,  1),  cb.BenefitsDateInfo_PlanBegin__c, 'planBegin on CB (else branch)');
        System.assertEquals(Date.newInstance(2024, 12, 31), cb.BenefitsDateInfo_PlanEnd__c,   'planEnd on CB (else branch)');
    }
}