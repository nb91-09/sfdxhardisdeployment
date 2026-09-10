/**
 * PPIA_QueryCareEpisodes
 * Invocable Apex class that queries care episodes for a list of patient
 * account IDs via the MIMIT Data360 API and returns aggregated metrics.
 * Used by the PPIA nightly Flow and Agentforce Action 3.
 */
public with sharing class PPIA_QueryCareEpisodes {

    // ─── Request / Result wrappers ───────────────────────────────────────────

    public class EpisodeRequest {
        @InvocableVariable(label='Patient Account IDs (CSV)' required=true)
        public String patientAccountIdsCsv;

        @InvocableVariable(label='Max Episodes to Return' required=false)
        public Integer limitCount;
    }

    public class EpisodeResult {
        @InvocableVariable public Integer totalEpisodes;
        @InvocableVariable public Integer episodesT12M;
        @InvocableVariable public Integer episodesT90D;
        @InvocableVariable public Integer episodesYTD;
        @InvocableVariable public Decimal totalBilled;
        @InvocableVariable public Decimal totalReceived;
        @InvocableVariable public Decimal collectionRate;
        @InvocableVariable public Decimal avgBilledPerEpisode;
        @InvocableVariable public Integer paApprovedCount;
        @InvocableVariable public Integer paDeniedCount;
        @InvocableVariable public Integer paPartialCount;
        @InvocableVariable public Decimal paApprovalRate;
        @InvocableVariable public Decimal denialRate;
        @InvocableVariable public Integer closedLostCount;
        @InvocableVariable public String topProcedure;
        @InvocableVariable public String topDiseaseState;
        @InvocableVariable public String errorMessage;
        @InvocableVariable public Boolean success;
    }

    // ─── Invocable entry point ───────────────────────────────────────────────

    @InvocableMethod(
        label='PPIA Query Care Episodes'
        description='Queries care episodes for a CSV list of patient Account IDs and returns aggregated PPIA metrics.'
    )
    public static List<EpisodeResult> queryEpisodes(List<EpisodeRequest> requests) {
        List<EpisodeResult> results = new List<EpisodeResult>();
        for (EpisodeRequest req : requests) {
            results.add(processRequest(req));
        }
        return results;
    }

    // ─── Core processing ─────────────────────────────────────────────────────

    private static EpisodeResult processRequest(EpisodeRequest req) {
        EpisodeResult res = new EpisodeResult();
        res.success = false;

        try {
            if (String.isBlank(req.patientAccountIdsCsv)) {
                res.errorMessage = 'patientAccountIdsCsv is required.';
                return res;
            }

            Integer maxRecords = (req.limitCount != null && req.limitCount > 0)
                ? req.limitCount : 500;

            // Build SOQL — queries ssot__Opportunity__dlm (Care Episodes)
            String accountIdList = buildInClause(req.patientAccountIdsCsv);
            String soql =
                'SELECT ssot__Id__c, ssot__OpportunityStageId__c, ' +
                '       Date_of_Service__c, Disease_State__c, ' +
                '       Pre_authorization_STATUS__c, ' +
                '       Pre_authorization_need_from_Payer__c, ' +
                '       ssot__TotalAmount__c, Primary_Amount__c, ' +
                '       Procedure_Category__c, AccountId__c ' +
                'FROM ssot__Opportunity__dlm ' +
                'WHERE AccountId__c IN (' + accountIdList + ') ' +
                'ORDER BY Date_of_Service__c DESC ' +
                'LIMIT ' + maxRecords;

            List<SObject> episodes = Database.query(soql);
            res = aggregateEpisodes(episodes);
            res.success = true;

        } catch (Exception e) {
            res.errorMessage = e.getMessage();
            res.success = false;
        }

        return res;
    }

    // ─── Aggregation logic ───────────────────────────────────────────────────

    @TestVisible
    private static EpisodeResult aggregateEpisodes(List<SObject> episodes) {
        EpisodeResult res = new EpisodeResult();

        Date today        = Date.today();
        Date t12MStart    = today.addYears(-1);
        Date t90DStart    = today.addDays(-90);
        Date ytdStart     = Date.newInstance(today.year(), 1, 1);

        Integer totalCount   = 0;
        Integer t12MCount    = 0;
        Integer t90DCount    = 0;
        Integer ytdCount     = 0;
        Decimal totalBilled  = 0;
        Decimal totalReceived = 0;
        Integer paApproved   = 0;
        Integer paDenied     = 0;
        Integer paPartial    = 0;
        Integer closedLost   = 0;

        Map<String, Integer> procedureCounts   = new Map<String, Integer>();
        Map<String, Integer> diseaseCounts     = new Map<String, Integer>();

        for (SObject ep : episodes) {
            totalCount++;

            // Date bucketing
            Date dos = (Date) ep.get('Date_of_Service__c');
            if (dos != null) {
                if (dos >= t12MStart) t12MCount++;
                if (dos >= t90DStart) t90DCount++;
                if (dos >= ytdStart)  ytdCount++;
            }

            // Financial
            Decimal billed   = (Decimal) ep.get('ssot__TotalAmount__c');
            Decimal received = (Decimal) ep.get('Primary_Amount__c');
            if (billed   != null && billed   > 0) totalBilled   += billed;
            if (received != null && received > 0) totalReceived += received;

            // PA status
            String paStatus = String.valueOf(ep.get('Pre_authorization_STATUS__c')).toLowerCase();
            String stageId  = String.valueOf(ep.get('ssot__OpportunityStageId__c')).toLowerCase();
            Boolean needsPA = 'true'.equalsIgnoreCase(
                String.valueOf(ep.get('Pre_authorization_need_from_Payer__c')));

            if (needsPA) {
                if (paStatus.contains('approved') || paStatus.contains('auth')) {
                    paApproved++;
                } else if (paStatus.contains('denied') || paStatus.contains('denied')) {
                    paDenied++;
                } else if (paStatus.contains('partial')) {
                    paPartial++;
                }
            }

            // Closed lost
            if (stageId.contains('closed lost') || stageId.contains('closedlost')) {
                closedLost++;
            }

            // Top procedure
            String proc = String.valueOf(ep.get('Procedure_Category__c'));
            if (String.isNotBlank(proc) && proc != 'null') {
                procedureCounts.put(proc, (procedureCounts.containsKey(proc)
                    ? procedureCounts.get(proc) : 0) + 1);
            }

            // Top disease state
            String disease = String.valueOf(ep.get('Disease_State__c'));
            if (String.isNotBlank(disease) && disease != 'null') {
                diseaseCounts.put(disease, (diseaseCounts.containsKey(disease)
                    ? diseaseCounts.get(disease) : 0) + 1);
            }
        }

        // Compute rates
        Integer totalPA = paApproved + paDenied + paPartial;
        Decimal paApprovalRate = (totalPA > 0)
            ? ((Decimal) paApproved / totalPA * 100).setScale(1) : 0;
        Decimal denialRate = (totalCount > 0)
            ? ((Decimal) closedLost / totalCount * 100).setScale(1) : 0;
        Decimal collectionRate = (totalBilled > 0)
            ? (totalReceived / totalBilled * 100).setScale(1) : 0;
        Decimal avgBilled = (totalCount > 0)
            ? (totalBilled / totalCount).setScale(2) : 0;

        // Assign
        res.totalEpisodes      = totalCount;
        res.episodesT12M       = t12MCount;
        res.episodesT90D       = t90DCount;
        res.episodesYTD        = ytdCount;
        res.totalBilled        = totalBilled.setScale(2);
        res.totalReceived      = totalReceived.setScale(2);
        res.collectionRate     = collectionRate;
        res.avgBilledPerEpisode = avgBilled;
        res.paApprovedCount    = paApproved;
        res.paDeniedCount      = paDenied;
        res.paPartialCount     = paPartial;
        res.paApprovalRate     = paApprovalRate;
        res.denialRate         = denialRate;
        res.closedLostCount    = closedLost;
        res.topProcedure       = getTopKey(procedureCounts);
        res.topDiseaseState    = getTopKey(diseaseCounts);

        return res;
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private static String buildInClause(String csv) {
        List<String> ids = csv.split(',');
        List<String> quoted = new List<String>();
        for (String id : ids) {
            String trimmed = id.trim();
            if (String.isNotBlank(trimmed)) {
                quoted.add('\'' + String.escapeSingleQuotes(trimmed) + '\'');
            }
        }
        return String.join(quoted, ',');
    }

    private static String getTopKey(Map<String, Integer> countMap) {
        String topKey = '';
        Integer topCount = 0;
        for (String key : countMap.keySet()) {
            if (countMap.get(key) > topCount) {
                topCount = countMap.get(key);
                topKey = key;
            }
        }
        return topKey;
    }
}