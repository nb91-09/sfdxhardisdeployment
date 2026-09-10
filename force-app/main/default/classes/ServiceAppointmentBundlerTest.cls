@isTest
public class ServiceAppointmentBundlerTest {

    // -----------------------------------------------------------------
    // HELPER METHODS - reusable across all test methods
    // -----------------------------------------------------------------

    private static ServiceTerritory createTerritory() {
        OperatingHours oh = new OperatingHours(Name = 'Test Hours', TimeZone = 'America/Chicago');
        insert oh;
        ServiceTerritory st = new ServiceTerritory(Name = 'Test Territory', IsActive = true, OperatingHoursId = oh.Id);
        insert st;
        return st;
    }

    private static WorkType createWorkType() {
        WorkType wt = new WorkType(
            Name              = 'Test Work Type',
            EstimatedDuration = 60,
            DurationType      = 'Minutes'
        );
        insert wt;
        return wt;
    }

    private static WorkOrder createWorkOrder(Id territoryId) {
        WorkOrder wo = new WorkOrder(Status = 'New', ServiceTerritoryId = territoryId);
        insert wo;
        return wo;
    }

    private static ServiceResource createServiceResource(Id userId) {
        ServiceResource sr = new ServiceResource(
            Name            = 'Test Resource ' + Crypto.getRandomInteger(),
            RelatedRecordId = userId,
            ResourceType    = 'T',
            IsActive        = true
        );
        insert sr;
        return sr;
    }

    private static ServiceResource createServiceResource() {
        return createServiceResource(UserInfo.getUserId());
    }

    // Creates a minimal active user so two distinct ServiceResources can be created
    private static User createTestUser() {
        User u = new User(
            LastName          = 'TestBundler' + Crypto.getRandomInteger(),
            Email             = 'testbundler' + Crypto.getRandomInteger() + '@example.com',
            Username          = 'testbundler' + Crypto.getRandomInteger() + '@example.testonly',
            Alias             = 'tbndl',
            TimeZoneSidKey    = 'America/Chicago',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = UserInfo.getProfileId()
        );
        insert u;
        return u;
    }

    // FSL requires a ServiceTerritoryMember before a regular SA can move to Scheduled/Dispatched
    private static void addMemberToTerritory(Id stId, Id srId) {
        insert new ServiceTerritoryMember(
            ServiceTerritoryId = stId,
            ServiceResourceId  = srId,
            EffectiveStartDate = Date.newInstance(2020, 1, 1)
        );
    }

    private static ServiceAppointment createSA(
        Id       woId,
        Id       territoryId,
        Id       workTypeId,
        String   zip,
        DateTime startTime,
        DateTime endTime
    ) {
        ServiceAppointment sa = new ServiceAppointment(
            ParentRecordId     = woId,
            ServiceTerritoryId = territoryId,
            WorkTypeId         = workTypeId,
            PostalCode         = zip,
            Street             = '100 Test Street',
            City               = 'Chicago',
            State              = 'Illinois',
            StateCode          = 'IL',
            Country            = 'United States',
            CountryCode        = 'US',
            SchedStartTime     = startTime,
            SchedEndTime       = endTime,
            EarliestStartTime  = startTime,
            DueDate            = endTime,
            Duration           = 60,
            DurationType       = 'Minutes'
        );
        insert sa;
        return sa;
    }

    // Transitions SA status: None -> Scheduled -> Dispatched
    // FSL blocks jumping directly from None to Dispatched
    private static void setDispatched(Id saId) {
        update new ServiceAppointment(Id = saId, Status = 'Scheduled');
        update new ServiceAppointment(Id = saId, Status = 'Dispatched');
    }

    // -----------------------------------------------------------------
    // TEST 1: Two SAs with same zip, provider, date -> bundle created
    // -----------------------------------------------------------------
    @isTest
    static void testBundleCreated_SameZipProviderDate() {
        ServiceTerritory st = createTerritory();
        WorkType         wt = createWorkType();

        ServiceResource sr = createServiceResource();
        addMemberToTerritory(st.Id, sr.Id);

        WorkOrder wo1 = createWorkOrder(st.Id);
        WorkOrder wo2 = createWorkOrder(st.Id);

        Date d = Date.today().addDays(3);
        DateTime start1 = DateTime.newInstanceGmt(d.year(), d.month(), d.day(), 14, 0, 0);
        DateTime end1   = DateTime.newInstanceGmt(d.year(), d.month(), d.day(), 15, 0, 0);
        DateTime start2 = DateTime.newInstanceGmt(d.year(), d.month(), d.day(), 16, 0, 0);
        DateTime end2   = DateTime.newInstanceGmt(d.year(), d.month(), d.day(), 17, 0, 0);

        ServiceAppointment sa1 = createSA(wo1.Id, st.Id, wt.Id, '60521', start1, end1);
        ServiceAppointment sa2 = createSA(wo2.Id, st.Id, wt.Id, '60521', start2, end2);

        insert new List<AssignedResource>{
            new AssignedResource(ServiceAppointmentId = sa1.Id, ServiceResourceId = sr.Id),
            new AssignedResource(ServiceAppointmentId = sa2.Id, ServiceResourceId = sr.Id)
        };

        Test.startTest();
        setDispatched(sa1.Id);
        ServiceAppointmentBundler.hasAlreadyRun = false;
        setDispatched(sa2.Id);
        Test.stopTest();

        List<ServiceAppointment> bundles = [
            SELECT Id, IsBundle, SchedStartTime, SchedEndTime
            FROM   ServiceAppointment
            WHERE  IsBundle = true
        ];
        System.assertEquals(1, bundles.size(), 'One bundle should be created');
        System.assertEquals(start1, bundles[0].SchedStartTime, 'Bundle start = earliest child start');
        System.assertEquals(end2,   bundles[0].SchedEndTime,   'Bundle end = latest child end');

        List<ServiceAppointment> children = [
            SELECT IsBundleMember, RelatedBundleId
            FROM   ServiceAppointment
            WHERE  Id IN (:sa1.Id, :sa2.Id)
        ];
        for (ServiceAppointment child : children) {
            System.assertEquals(true,          child.IsBundleMember,  'IsBundleMember must be true on child');
            System.assertEquals(bundles[0].Id, child.RelatedBundleId, 'RelatedBundleId must point to parent bundle');
        }
    }

    // -----------------------------------------------------------------
    // TEST 2: Two SAs with different zip codes -> no bundle
    // -----------------------------------------------------------------
    @isTest
    static void testNoBundle_DifferentZipCode() {
        ServiceTerritory st = createTerritory();
        WorkType         wt = createWorkType();

        ServiceResource sr = createServiceResource();
        addMemberToTerritory(st.Id, sr.Id);

        WorkOrder wo1 = createWorkOrder(st.Id);
        WorkOrder wo2 = createWorkOrder(st.Id);

        DateTime start = DateTime.newInstanceGmt(2026, 6, 2, 14, 0, 0);
        DateTime endDt = DateTime.newInstanceGmt(2026, 6, 2, 15, 0, 0);

        ServiceAppointment sa1 = createSA(wo1.Id, st.Id, wt.Id, '60521', start, endDt);
        ServiceAppointment sa2 = createSA(wo2.Id, st.Id, wt.Id, '60016', start, endDt);

        insert new List<AssignedResource>{
            new AssignedResource(ServiceAppointmentId = sa1.Id, ServiceResourceId = sr.Id),
            new AssignedResource(ServiceAppointmentId = sa2.Id, ServiceResourceId = sr.Id)
        };

        Test.startTest();
        setDispatched(sa1.Id);
        ServiceAppointmentBundler.hasAlreadyRun = false;
        setDispatched(sa2.Id);
        Test.stopTest();

        List<ServiceAppointment> bundles = [SELECT Id FROM ServiceAppointment WHERE IsBundle = true];
        System.assertEquals(0, bundles.size(), 'No bundle should be created for different zip codes');
    }

    // -----------------------------------------------------------------
    // TEST 3: Two SAs with different providers -> no bundle
    // -----------------------------------------------------------------
    @isTest
    static void testNoBundle_DifferentProvider() {
        ServiceTerritory st = createTerritory();
        WorkType         wt = createWorkType();

        ServiceResource sr1 = createServiceResource();
        ServiceResource sr2 = createServiceResource(createTestUser().Id);
        addMemberToTerritory(st.Id, sr1.Id);
        addMemberToTerritory(st.Id, sr2.Id);

        WorkOrder wo1 = createWorkOrder(st.Id);
        WorkOrder wo2 = createWorkOrder(st.Id);

        DateTime start = DateTime.newInstanceGmt(2026, 6, 3, 14, 0, 0);
        DateTime endDt = DateTime.newInstanceGmt(2026, 6, 3, 15, 0, 0);

        ServiceAppointment sa1 = createSA(wo1.Id, st.Id, wt.Id, '60521', start, endDt);
        ServiceAppointment sa2 = createSA(wo2.Id, st.Id, wt.Id, '60521', start, endDt);

        insert new List<AssignedResource>{
            new AssignedResource(ServiceAppointmentId = sa1.Id, ServiceResourceId = sr1.Id),
            new AssignedResource(ServiceAppointmentId = sa2.Id, ServiceResourceId = sr2.Id)
        };

        Test.startTest();
        setDispatched(sa1.Id);
        ServiceAppointmentBundler.hasAlreadyRun = false;
        setDispatched(sa2.Id);
        Test.stopTest();

        List<ServiceAppointment> bundles = [SELECT Id FROM ServiceAppointment WHERE IsBundle = true];
        System.assertEquals(0, bundles.size(), 'No bundle should be created for different providers');
    }

    // -----------------------------------------------------------------
    // TEST 4: Two SAs with different dates -> no bundle
    // -----------------------------------------------------------------
    @isTest
    static void testNoBundle_DifferentDate() {
        ServiceTerritory st = createTerritory();
        WorkType         wt = createWorkType();

        ServiceResource sr = createServiceResource();
        addMemberToTerritory(st.Id, sr.Id);

        WorkOrder wo1 = createWorkOrder(st.Id);
        WorkOrder wo2 = createWorkOrder(st.Id);

        DateTime start1 = DateTime.newInstanceGmt(2026, 6, 4, 14, 0, 0);
        DateTime end1   = DateTime.newInstanceGmt(2026, 6, 4, 15, 0, 0);
        DateTime start2 = DateTime.newInstanceGmt(2026, 6, 5, 14, 0, 0);
        DateTime end2   = DateTime.newInstanceGmt(2026, 6, 5, 15, 0, 0);

        ServiceAppointment sa1 = createSA(wo1.Id, st.Id, wt.Id, '60521', start1, end1);
        ServiceAppointment sa2 = createSA(wo2.Id, st.Id, wt.Id, '60521', start2, end2);

        insert new List<AssignedResource>{
            new AssignedResource(ServiceAppointmentId = sa1.Id, ServiceResourceId = sr.Id),
            new AssignedResource(ServiceAppointmentId = sa2.Id, ServiceResourceId = sr.Id)
        };

        Test.startTest();
        setDispatched(sa1.Id);
        ServiceAppointmentBundler.hasAlreadyRun = false;
        setDispatched(sa2.Id);
        Test.stopTest();

        List<ServiceAppointment> bundles = [SELECT Id FROM ServiceAppointment WHERE IsBundle = true];
        System.assertEquals(0, bundles.size(), 'No bundle should be created for different dates');
    }

    // -----------------------------------------------------------------
    // TEST 5: Only one SA -> no bundle (minimum 2 required)
    // -----------------------------------------------------------------
    @isTest
    static void testNoBundle_SingleSA() {
        ServiceTerritory st = createTerritory();
        WorkType         wt = createWorkType();

        ServiceResource sr = createServiceResource();
        addMemberToTerritory(st.Id, sr.Id);

        WorkOrder wo = createWorkOrder(st.Id);

        DateTime start = DateTime.newInstanceGmt(2026, 6, 6, 14, 0, 0);
        DateTime endDt = DateTime.newInstanceGmt(2026, 6, 6, 15, 0, 0);

        ServiceAppointment sa = createSA(wo.Id, st.Id, wt.Id, '60521', start, endDt);
        insert new AssignedResource(ServiceAppointmentId = sa.Id, ServiceResourceId = sr.Id);

        Test.startTest();
        setDispatched(sa.Id);
        Test.stopTest();

        List<ServiceAppointment> bundles = [SELECT Id FROM ServiceAppointment WHERE IsBundle = true];
        System.assertEquals(0, bundles.size(), 'No bundle should be created for a single SA');
    }

    // -----------------------------------------------------------------
    // TEST 6: Two bundles created for two different groups
    // -----------------------------------------------------------------
    /*@isTest
    static void testTwoBundlesCreated_TwoGroups() {
        ServiceTerritory st = createTerritory();
        WorkType         wt = createWorkType();

        ServiceResource sr1 = createServiceResource();
        ServiceResource sr2 = createServiceResource(createTestUser().Id);
        addMemberToTerritory(st.Id, sr1.Id);
        addMemberToTerritory(st.Id, sr2.Id);

        WorkOrder wo1 = createWorkOrder(st.Id);
        WorkOrder wo2 = createWorkOrder(st.Id);
        WorkOrder wo3 = createWorkOrder(st.Id);
        WorkOrder wo4 = createWorkOrder(st.Id);

        DateTime start = DateTime.now().addDays(7);
        DateTime endDt = DateTime.now().addDays(7).addHours(1);

        ServiceAppointment sa1 = createSA(wo1.Id, st.Id, wt.Id, '60521', start, endDt);
        ServiceAppointment sa2 = createSA(wo2.Id, st.Id, wt.Id, '60521', start, endDt);
        ServiceAppointment sa3 = createSA(wo3.Id, st.Id, wt.Id, '60016', start, endDt);
        ServiceAppointment sa4 = createSA(wo4.Id, st.Id, wt.Id, '60016', start, endDt);

        insert new List<AssignedResource>{
            new AssignedResource(ServiceAppointmentId = sa1.Id, ServiceResourceId = sr1.Id),
            new AssignedResource(ServiceAppointmentId = sa2.Id, ServiceResourceId = sr1.Id),
            new AssignedResource(ServiceAppointmentId = sa3.Id, ServiceResourceId = sr2.Id),
            new AssignedResource(ServiceAppointmentId = sa4.Id, ServiceResourceId = sr2.Id)
        };

        Test.startTest();
        setDispatched(sa1.Id);
        ServiceAppointmentBundler.hasAlreadyRun = false;
        setDispatched(sa2.Id);
        ServiceAppointmentBundler.hasAlreadyRun = false;
        setDispatched(sa3.Id);
        ServiceAppointmentBundler.hasAlreadyRun = false;
        setDispatched(sa4.Id);
        Test.stopTest();

        List<ServiceAppointment> bundles = [SELECT Id FROM ServiceAppointment WHERE IsBundle = true];
        System.assertEquals(2, bundles.size(), 'Two separate bundles should be created for two groups');
    }*/

    // -----------------------------------------------------------------
    // TEST 7: New SA appended to existing bundle
    // -----------------------------------------------------------------
    @isTest
    static void testAppendToExistingBundle() {
        ServiceTerritory st = createTerritory();
        WorkType         wt = createWorkType();

        ServiceResource sr = createServiceResource();
        addMemberToTerritory(st.Id, sr.Id);

        WorkOrder woBundleParent = createWorkOrder(st.Id);
        WorkOrder wo3            = createWorkOrder(st.Id);

        // Anchor to a fixed mid-day GMT hour (instead of DateTime.now() + offset)
        // so the date portion of the bundler's grouping key can never roll over
        // into the next GMT calendar date depending on when the test happens to run.
        Date d = Date.today().addDays(8);
        DateTime start1 = DateTime.newInstanceGmt(d.year(), d.month(), d.day(), 9, 0, 0);
        DateTime end1   = DateTime.newInstanceGmt(d.year(), d.month(), d.day(), 10, 0, 0);
        DateTime start3 = DateTime.newInstanceGmt(d.year(), d.month(), d.day(), 12, 0, 0);
        DateTime end3   = DateTime.newInstanceGmt(d.year(), d.month(), d.day(), 13, 0, 0);

        // Manually create a parent bundle SA - avoids the multi-step bundler chain that hits FSL SOQL limits
        ServiceAppointment parentBundle = createSA(woBundleParent.Id, st.Id, wt.Id, '60521', start1, end1);
        update new ServiceAppointment(Id = parentBundle.Id, Status = 'Scheduled', IsBundle = true);
        update new ServiceAppointment(Id = parentBundle.Id, Status = 'Dispatched');
        insert new AssignedResource(ServiceAppointmentId = parentBundle.Id, ServiceResourceId = sr.Id);

        // Create sa3 - same zip / resource / date as the existing bundle
        ServiceAppointment sa3 = createSA(wo3.Id, st.Id, wt.Id, '60521', start3, end3);
        insert new AssignedResource(ServiceAppointmentId = sa3.Id, ServiceResourceId = sr.Id);

        Test.startTest();
        ServiceAppointmentBundler.hasAlreadyRun = false;
        setDispatched(sa3.Id);
        Test.stopTest();

        ServiceAppointment sa3Result = [
            SELECT IsBundleMember, RelatedBundleId
            FROM   ServiceAppointment
            WHERE  Id = :sa3.Id
        ];
        System.assertEquals(true,            sa3Result.IsBundleMember,  'SA3 should be tagged as bundle member');
        System.assertEquals(parentBundle.Id, sa3Result.RelatedBundleId, 'SA3 should be linked to the existing bundle');

        List<ServiceAppointment> bundlesAfter = [SELECT Id FROM ServiceAppointment WHERE IsBundle = true];
        System.assertEquals(1, bundlesAfter.size(), 'No duplicate bundle should be created');
    }

    // -----------------------------------------------------------------
    // TEST 8: Trigger does NOT run when SA is already a bundle parent
    // -----------------------------------------------------------------
    @isTest
    static void testTrigger_SkipsBundleParent() {
        ServiceTerritory st = createTerritory();
        WorkType         wt = createWorkType();
        WorkOrder        wo = createWorkOrder(st.Id);

        DateTime start = DateTime.newInstanceGmt(2026, 6, 9, 14, 0, 0);
        DateTime endDt = DateTime.newInstanceGmt(2026, 6, 9, 15, 0, 0);

        ServiceAppointment bundleSA = createSA(wo.Id, st.Id, wt.Id, '60521', start, endDt);
        update new ServiceAppointment(Id = bundleSA.Id, Status = 'Scheduled', IsBundle = true);

        Test.startTest();
        ServiceAppointmentBundler.hasAlreadyRun = false;
        update new ServiceAppointment(Id = bundleSA.Id, Status = 'Dispatched');
        Test.stopTest();

        System.assertEquals(false, ServiceAppointmentBundler.hasAlreadyRun, 'Bundler should NOT run for bundle parents');
    }

    // -----------------------------------------------------------------
    // TEST 9: Trigger does NOT run when SA is already a bundle member
    // -----------------------------------------------------------------
    @isTest
    static void testTrigger_SkipsBundleMember() {
        ServiceTerritory st = createTerritory();
        WorkType         wt = createWorkType();
        WorkOrder        wo1 = createWorkOrder(st.Id);
        WorkOrder        wo2 = createWorkOrder(st.Id);

        DateTime start = DateTime.newInstanceGmt(2026, 6, 10, 14, 0, 0);
        DateTime endDt = DateTime.newInstanceGmt(2026, 6, 10, 15, 0, 0);

        // Create a parent bundle SA first (FSL allows Scheduled+IsBundle=true in one update)
        ServiceAppointment parentSA = createSA(wo1.Id, st.Id, wt.Id, '60521', start, endDt);
        update new ServiceAppointment(Id = parentSA.Id, Status = 'Scheduled', IsBundle = true);

        // Create member SA, link it to the parent
        ServiceAppointment memberSA = createSA(wo2.Id, st.Id, wt.Id, '60521', start, endDt);
        update new ServiceAppointment(Id = memberSA.Id, RelatedBundleId = parentSA.Id, IsBundleMember = true);

        Test.startTest();
        ServiceAppointmentBundler.hasAlreadyRun = false;
        // Status update on a bundle member - trigger should skip it
        update new ServiceAppointment(Id = memberSA.Id, Status = 'Scheduled');
        Test.stopTest();

        System.assertEquals(false, ServiceAppointmentBundler.hasAlreadyRun, 'Bundler should NOT run for bundle members');
    }

    // -----------------------------------------------------------------
    // TEST 10: Trigger does NOT run on status update that is NOT Dispatched
    // -----------------------------------------------------------------
    @isTest
    static void testTrigger_SkipsNonDispatchedUpdate() {
        ServiceTerritory st = createTerritory();
        WorkType         wt = createWorkType();
        WorkOrder        wo = createWorkOrder(st.Id);

        ServiceResource sr = createServiceResource();
        addMemberToTerritory(st.Id, sr.Id);

        DateTime start = DateTime.newInstanceGmt(2026, 6, 11, 14, 0, 0);
        DateTime endDt = DateTime.newInstanceGmt(2026, 6, 11, 15, 0, 0);

        ServiceAppointment sa = createSA(wo.Id, st.Id, wt.Id, '60521', start, endDt);
        insert new AssignedResource(ServiceAppointmentId = sa.Id, ServiceResourceId = sr.Id);

        Test.startTest();
        ServiceAppointmentBundler.hasAlreadyRun = false;
        update new ServiceAppointment(Id = sa.Id, Status = 'Scheduled');
        Test.stopTest();

        System.assertEquals(false, ServiceAppointmentBundler.hasAlreadyRun, 'Bundler should NOT run for non-Dispatched status');
    }

    // -----------------------------------------------------------------
    // TEST 11: SA dispatched without zip -> zip added later -> bundle created
    // -----------------------------------------------------------------
    @isTest
    static void testBundle_ZipPopulatedAfterDispatched() {
        ServiceTerritory st = createTerritory();
        WorkType         wt = createWorkType();

        ServiceResource sr = createServiceResource();
        addMemberToTerritory(st.Id, sr.Id);

        WorkOrder wo1 = createWorkOrder(st.Id);
        WorkOrder wo2 = createWorkOrder(st.Id);

        DateTime start = DateTime.now().addDays(10);
        DateTime endDt = DateTime.now().addDays(10).addHours(1);

        // Create SAs WITHOUT PostalCode - bundler must not fire on dispatch
        ServiceAppointment sa1 = new ServiceAppointment(
            ParentRecordId    = wo1.Id,
            ServiceTerritoryId = st.Id,
            WorkTypeId        = wt.Id,
            Street            = '100 Test Street',
            City              = 'Chicago',
            State             = 'Illinois',
            StateCode         = 'IL',
            Country           = 'United States',
            CountryCode       = 'US',
            SchedStartTime    = start,
            SchedEndTime      = endDt,
            EarliestStartTime = start,
            DueDate           = endDt,
            Duration          = 60,
            DurationType      = 'Minutes'
        );
        ServiceAppointment sa2 = new ServiceAppointment(
            ParentRecordId    = wo2.Id,
            ServiceTerritoryId = st.Id,
            WorkTypeId        = wt.Id,
            Street            = '100 Test Street',
            City              = 'Chicago',
            State             = 'Illinois',
            StateCode         = 'IL',
            Country           = 'United States',
            CountryCode       = 'US',
            SchedStartTime    = start,
            SchedEndTime      = endDt,
            EarliestStartTime = start,
            DueDate           = endDt,
            Duration          = 60,
            DurationType      = 'Minutes'
        );
        insert new List<ServiceAppointment>{ sa1, sa2 };

        insert new List<AssignedResource>{
            new AssignedResource(ServiceAppointmentId = sa1.Id, ServiceResourceId = sr.Id),
            new AssignedResource(ServiceAppointmentId = sa2.Id, ServiceResourceId = sr.Id)
        };

        // Dispatch both - bundler skips them because PostalCode is null
        setDispatched(sa1.Id);
        ServiceAppointmentBundler.hasAlreadyRun = false;
        setDispatched(sa2.Id);
        ServiceAppointmentBundler.hasAlreadyRun = false;

        List<ServiceAppointment> bundlesBefore = [SELECT Id FROM ServiceAppointment WHERE IsBundle = true];
        System.assertEquals(0, bundlesBefore.size(), 'No bundle should exist before zip is populated');

        // Now populate PostalCode on both - trigger detects zip changed on Dispatched SAs -> bundler fires
        Test.startTest();
        ServiceAppointmentBundler.hasAlreadyRun = false;
        update new List<ServiceAppointment>{
            new ServiceAppointment(Id = sa1.Id, PostalCode = '60521'),
            new ServiceAppointment(Id = sa2.Id, PostalCode = '60521')
        };
        Test.stopTest();

        List<ServiceAppointment> bundles = [SELECT Id FROM ServiceAppointment WHERE IsBundle = true];
        System.assertEquals(1, bundles.size(), 'Bundle should be created after zip is populated');

        List<ServiceAppointment> children = [
            SELECT IsBundleMember, RelatedBundleId
            FROM   ServiceAppointment
            WHERE  Id IN (:sa1.Id, :sa2.Id)
        ];
        for (ServiceAppointment child : children) {
            System.assertEquals(true,          child.IsBundleMember,  'Child should be a bundle member');
            System.assertEquals(bundles[0].Id, child.RelatedBundleId, 'Child should reference the bundle');
        }
    }

    // -----------------------------------------------------------------
    // TEST 12: SA dispatched with zip A -> zip changes to zip B -> bundle created with zip B group
    // -----------------------------------------------------------------
    @isTest
    static void testBundle_ZipChangedWhileDispatched() {
        ServiceTerritory st = createTerritory();
        WorkType         wt = createWorkType();

        ServiceResource sr = createServiceResource();
        addMemberToTerritory(st.Id, sr.Id);

        WorkOrder wo1 = createWorkOrder(st.Id);
        WorkOrder wo2 = createWorkOrder(st.Id);

        DateTime start = DateTime.now().addDays(5);
        DateTime endDt = DateTime.now().addDays(5).addHours(1);

        // SA1 starts with zip 60521, SA2 has zip 60016 - different zips so no bundle on dispatch
        ServiceAppointment sa1 = createSA(wo1.Id, st.Id, wt.Id, '60521', start, endDt);
        ServiceAppointment sa2 = createSA(wo2.Id, st.Id, wt.Id, '60016', start, endDt);

        insert new List<AssignedResource>{
            new AssignedResource(ServiceAppointmentId = sa1.Id, ServiceResourceId = sr.Id),
            new AssignedResource(ServiceAppointmentId = sa2.Id, ServiceResourceId = sr.Id)
        };

        // Dispatch both - each alone in their zip, no bundle formed
        setDispatched(sa1.Id);
        ServiceAppointmentBundler.hasAlreadyRun = false;
        setDispatched(sa2.Id);
        ServiceAppointmentBundler.hasAlreadyRun = false;

        List<ServiceAppointment> bundlesBefore = [SELECT Id FROM ServiceAppointment WHERE IsBundle = true];
        System.assertEquals(0, bundlesBefore.size(), 'No bundle should exist before zip change');

        // Update SA1 zip from 60521 -> 60016 - trigger detects zipJustChanged and fires bundler
        Test.startTest();
        ServiceAppointmentBundler.hasAlreadyRun = false;
        update new ServiceAppointment(Id = sa1.Id, PostalCode = '60016');
        Test.stopTest();

        List<ServiceAppointment> bundles = [SELECT Id FROM ServiceAppointment WHERE IsBundle = true];
        System.assertEquals(1, bundles.size(), 'Bundle should be created after zip change');

        List<ServiceAppointment> children = [
            SELECT IsBundleMember, RelatedBundleId
            FROM   ServiceAppointment
            WHERE  Id IN (:sa1.Id, :sa2.Id)
        ];
        for (ServiceAppointment child : children) {
            System.assertEquals(true,          child.IsBundleMember,  'Child should be a bundle member');
            System.assertEquals(bundles[0].Id, child.RelatedBundleId, 'Child should reference the bundle');
        }
    }
}