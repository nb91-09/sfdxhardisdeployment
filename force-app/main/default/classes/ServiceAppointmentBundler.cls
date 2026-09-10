public class ServiceAppointmentBundler {

    // Prevents the trigger from firing recursively when bundler's own DML runs
    public static Boolean hasAlreadyRun = false;

    @InvocableMethod(
        label='Bundle Service Appointments'
        description='Groups eligible Service Appointments by zip code, assigned resource, and scheduled date. Appends to existing bundles when found, or creates new ones.'
    )
    public static void bundleServiceAppointments() {
        runBundler(null);
    }

    // Called by the trigger — scopes queries to only the zip codes of the changed SAs
    public static void bundleForTrigger(Set<Id> triggerSAIds) {
        Set<String> zipFilter = new Set<String>();
        for (ServiceAppointment sa : [
            SELECT PostalCode
            FROM   ServiceAppointment
            WHERE  Id IN :triggerSAIds
            AND    PostalCode != null
        ]) {
            zipFilter.add(sa.PostalCode);
        }
        if (!zipFilter.isEmpty()) {
            runBundler(zipFilter);
        }
    }

    private static void runBundler(Set<String> zipFilter) {

        // ─── Step 1: Query all eligible (unbundled, scheduled) Service Appointments ───
        // Only look at appointments scheduled today or within the next 30 days
        // to prevent unbounded growth of query results over time
        DateTime windowStart = DateTime.now();
        DateTime windowEnd   = DateTime.now().addDays(30);

        List<ServiceAppointment> eligibleSAs = zipFilter == null
            ? [
                SELECT Id, PostalCode, Street, City, State, StateCode,
                       Country, CountryCode, SchedStartTime, SchedEndTime,
                       ServiceTerritoryId, WorkTypeId, EarliestStartTime, DueDate
                FROM   ServiceAppointment
                WHERE  IsBundle       = false
                AND    IsBundleMember = false
                AND    SchedStartTime != null
                AND    PostalCode     != null
                AND    Status         = 'Dispatched'
                AND    SchedStartTime >= :windowStart
                AND    SchedStartTime <= :windowEnd
              ]
            : [
                SELECT Id, PostalCode, Street, City, State, StateCode,
                       Country, CountryCode, SchedStartTime, SchedEndTime,
                       ServiceTerritoryId, WorkTypeId, EarliestStartTime, DueDate
                FROM   ServiceAppointment
                WHERE  IsBundle       = false
                AND    IsBundleMember = false
                AND    SchedStartTime != null
                AND    PostalCode     != null
                AND    PostalCode     IN :zipFilter
                AND    Status         = 'Dispatched'
                AND    SchedStartTime >= :windowStart
                AND    SchedStartTime <= :windowEnd
              ];

        if (eligibleSAs.isEmpty()) {
            return;
        }

        // ─── Step 2: Query all existing parent bundle appointments ───
        List<ServiceAppointment> existingBundles = zipFilter == null
            ? [
                SELECT Id, PostalCode, Street, SchedStartTime, SchedEndTime
                FROM   ServiceAppointment
                WHERE  IsBundle       = true
                AND    SchedStartTime != null
                AND    PostalCode     != null
                AND    Status         = 'Dispatched'
                AND    SchedStartTime >= :windowStart
                AND    SchedStartTime <= :windowEnd
              ]
            : [
                SELECT Id, PostalCode, Street, SchedStartTime, SchedEndTime
                FROM   ServiceAppointment
                WHERE  IsBundle       = true
                AND    SchedStartTime != null
                AND    PostalCode     != null
                AND    PostalCode     IN :zipFilter
                AND    Status         = 'Dispatched'
                AND    SchedStartTime >= :windowStart
                AND    SchedStartTime <= :windowEnd
              ];

        Map<Id, ServiceAppointment> existingBundleById = new Map<Id, ServiceAppointment>(existingBundles);

        // ─── Step 3: Query Assigned Resources for eligible SAs and existing bundles ───
        Set<Id> allRelevantIds = new Set<Id>();
        allRelevantIds.addAll(new Map<Id, ServiceAppointment>(eligibleSAs).keySet());
        allRelevantIds.addAll(existingBundleById.keySet());

        Map<Id, AssignedResource> saIdToAR = new Map<Id, AssignedResource>();
        for (AssignedResource ar : [
            SELECT Id, ServiceAppointmentId, ServiceResourceId
            FROM   AssignedResource
            WHERE  ServiceAppointmentId IN :allRelevantIds
        ]) {
            saIdToAR.put(ar.ServiceAppointmentId, ar);
        }

        // ─── Step 4: Build existing bundle lookup — groupKey → bundle Id ───
        // Key: PostalCode + ResourceId + ScheduledDate (date only) + Street (exact match)
        Map<String, Id> existingBundleKeyToId = new Map<String, Id>();
        for (ServiceAppointment bundle : existingBundles) {
            AssignedResource ar = saIdToAR.get(bundle.Id);
            if (ar == null) continue;
            String key = buildGroupKey(bundle.PostalCode, ar.ServiceResourceId, bundle.SchedStartTime.dateGmt(), bundle.Street);
            // Keep only the first bundle found per key to avoid duplicates
            if (!existingBundleKeyToId.containsKey(key)) {
                existingBundleKeyToId.put(key, bundle.Id);
            }
        }

        // ─── Step 5: Categorise each eligible SA ───
        // → Matches an existing bundle  →  append to it
        // → No existing bundle          →  collect for new bundle creation

        Map<Id, List<ServiceAppointment>>     appendToBundle = new Map<Id, List<ServiceAppointment>>();
        Map<String, List<ServiceAppointment>> newGroupMap    = new Map<String, List<ServiceAppointment>>();

        for (ServiceAppointment sa : eligibleSAs) {
            AssignedResource ar = saIdToAR.get(sa.Id);
            if (ar == null) continue; // no assigned resource — skip

            String key = buildGroupKey(sa.PostalCode, ar.ServiceResourceId, sa.SchedStartTime.dateGmt(), sa.Street);

            if (existingBundleKeyToId.containsKey(key)) {
                Id bundleId = existingBundleKeyToId.get(key);
                if (!appendToBundle.containsKey(bundleId)) {
                    appendToBundle.put(bundleId, new List<ServiceAppointment>());
                }
                appendToBundle.get(bundleId).add(sa);
            } else {
                if (!newGroupMap.containsKey(key)) {
                    newGroupMap.put(key, new List<ServiceAppointment>());
                }
                newGroupMap.get(key).add(sa);
            }
        }

        // ─── Step 6: Append new SAs to existing bundles ───
        List<ServiceAppointment> childSAsToUpdate  = new List<ServiceAppointment>();
        List<ServiceAppointment> bundleSAsToUpdate = new List<ServiceAppointment>();
        List<AssignedResource>   childARsToDelete  = new List<AssignedResource>();

        for (Id bundleId : appendToBundle.keySet()) {
            ServiceAppointment       bundle  = existingBundleById.get(bundleId);
            List<ServiceAppointment> newKids = appendToBundle.get(bundleId);

            DateTime consolidatedStart = bundle.SchedStartTime;
            DateTime consolidatedEnd   = bundle.SchedEndTime != null ? bundle.SchedEndTime : bundle.SchedStartTime;

            for (ServiceAppointment sa : newKids) {
                // Tag child to existing bundle
                childSAsToUpdate.add(new ServiceAppointment(
                    Id              = sa.Id,
                    RelatedBundleId = bundleId,
                    IsBundleMember  = true
                ));

                // Remove assigned resource from child
                AssignedResource childAR = saIdToAR.get(sa.Id);
                if (childAR != null) {
                    childARsToDelete.add(childAR);
                }

                // Extend the bundle's time window if needed
                if (sa.SchedStartTime < consolidatedStart) {
                    consolidatedStart = sa.SchedStartTime;
                }
                if (sa.SchedEndTime != null && sa.SchedEndTime > consolidatedEnd) {
                    consolidatedEnd = sa.SchedEndTime;
                }
            }

            // Update bundle times only if they changed
            if (consolidatedStart != bundle.SchedStartTime || consolidatedEnd != bundle.SchedEndTime) {
                Decimal newDuration = (consolidatedEnd.getTime() - consolidatedStart.getTime()) / 60000.0;
                bundleSAsToUpdate.add(new ServiceAppointment(
                    Id             = bundleId,
                    SchedStartTime = consolidatedStart,
                    SchedEndTime   = consolidatedEnd,
                    Duration       = newDuration,
                    DurationType   = 'Minutes'
                ));
            }
        }

        // ─── Step 7: Create new parent bundles for unmatched groups (2 or more SAs) ───
        List<ServiceAppointment> parentSAsToInsert = new List<ServiceAppointment>();
        List<String>             processedKeys     = new List<String>();

        for (String key : newGroupMap.keySet()) {
            List<ServiceAppointment> saGroup = newGroupMap.get(key);
            if (saGroup.size() < 2) continue; // single SA — nothing to bundle yet

            processedKeys.add(key);

            DateTime consolidatedStart = saGroup[0].SchedStartTime;
            DateTime consolidatedEnd   = saGroup[0].SchedEndTime != null ? saGroup[0].SchedEndTime : saGroup[0].SchedStartTime;

            for (ServiceAppointment sa : saGroup) {
                if (sa.SchedStartTime < consolidatedStart) consolidatedStart = sa.SchedStartTime;
                if (sa.SchedEndTime != null && sa.SchedEndTime > consolidatedEnd) consolidatedEnd = sa.SchedEndTime;
            }

            Decimal durationMinutes = (consolidatedEnd.getTime() - consolidatedStart.getTime()) / 60000.0;

            ServiceAppointment ref = saGroup[0];
            parentSAsToInsert.add(new ServiceAppointment(
                SchedStartTime     = consolidatedStart,
                SchedEndTime       = consolidatedEnd,
                EarliestStartTime  = consolidatedStart,
                DueDate            = consolidatedEnd,
                Duration           = durationMinutes,
                DurationType       = 'Minutes',
                Street             = ref.Street,
                City               = ref.City,
                State              = ref.State,
                StateCode          = ref.StateCode,
                Country            = ref.Country,
                CountryCode        = ref.CountryCode,
                PostalCode         = ref.PostalCode,
                ServiceTerritoryId = ref.ServiceTerritoryId,
                WorkTypeId         = ref.WorkTypeId
            ));
        }

        // ─── Step 8: DML — ordered to satisfy dependencies ───

        // Update existing bundles with new consolidated times
        if (!bundleSAsToUpdate.isEmpty()) {
            update bundleSAsToUpdate;
        }

        // Create one Work Order (no Account) per parent bundle SA and link it as ParentRecordId
        if (!parentSAsToInsert.isEmpty()) {
            List<WorkOrder> bundleWorkOrders = new List<WorkOrder>();
            for (Integer i = 0; i < parentSAsToInsert.size(); i++) {
                bundleWorkOrders.add(new WorkOrder(Status = 'New'));
            }
            insert bundleWorkOrders;
            for (Integer i = 0; i < parentSAsToInsert.size(); i++) {
                parentSAsToInsert[i].ParentRecordId = bundleWorkOrders[i].Id;
            }
        }

        // Insert new parent bundle SAs (required before tagging children to them)
        if (!parentSAsToInsert.isEmpty()) {
            insert parentSAsToInsert;
            // Status transition: None → Scheduled → Dispatched (direct jump is blocked by FSL validation)
            // Step 1: Set IsBundle = true and move to Scheduled
            List<ServiceAppointment> scheduledUpdate = new List<ServiceAppointment>();
            for (ServiceAppointment parent : parentSAsToInsert) {
                scheduledUpdate.add(new ServiceAppointment(Id = parent.Id, IsBundle = true, Status = 'Scheduled'));
            }
            update scheduledUpdate;
            // Step 2: Move to Dispatched
            List<ServiceAppointment> dispatchedUpdate = new List<ServiceAppointment>();
            for (ServiceAppointment parent : parentSAsToInsert) {
                dispatchedUpdate.add(new ServiceAppointment(Id = parent.Id, Status = 'Dispatched'));
            }
            update dispatchedUpdate;
        }

        // Build child updates and parent ARs for newly created bundles
        List<AssignedResource> parentARsToInsert = new List<AssignedResource>();

        for (Integer i = 0; i < processedKeys.size(); i++) {
            String                   key      = processedKeys[i];
            Id                       parentId = parentSAsToInsert[i].Id;
            List<ServiceAppointment> saGroup  = newGroupMap.get(key);
            Boolean                  parentARCreated = false;

            for (ServiceAppointment sa : saGroup) {
                childSAsToUpdate.add(new ServiceAppointment(
                    Id              = sa.Id,
                    RelatedBundleId = parentId,
                    IsBundleMember  = true
                ));

                AssignedResource ar = saIdToAR.get(sa.Id);
                if (ar != null) {
                    if (!parentARCreated) {
                        parentARsToInsert.add(new AssignedResource(
                            ServiceAppointmentId = parentId,
                            ServiceResourceId    = ar.ServiceResourceId
                        ));
                        parentARCreated = true;
                    }
                    childARsToDelete.add(ar);
                }
            }
        }

        if (!childSAsToUpdate.isEmpty())  { update childSAsToUpdate;  }
        if (!parentARsToInsert.isEmpty()) { insert parentARsToInsert; }
        if (!childARsToDelete.isEmpty())  { delete childARsToDelete;  }
    }

    private static String buildGroupKey(String postalCode, Id resourceId, Date schedDate, String street) {
        String normalizedStreet = street != null ? street.trim().toLowerCase() : '';
        return postalCode + '_' + resourceId + '_' + String.valueOf(schedDate) + '_' + normalizedStreet;
    }
}