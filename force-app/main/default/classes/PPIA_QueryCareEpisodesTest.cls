/**
 * PPIA_QueryCareEpisodesTest
 * Unit tests for PPIA_QueryCareEpisodes.
 * Tests aggregation logic directly via @TestVisible methods
 * to avoid dependency on ssot__Opportunity__dlm in sandbox.
 */
@IsTest
private class PPIA_QueryCareEpisodesTest {

    // ─── Helper: build a mock SObject list ───────────────────────────────────
    // We use the aggregateEpisodes() method directly which accepts List<SObject>.
    // Since ssot__Opportunity__dlm may not be queryable in all sandboxes,
    // we test the invocable with a blank CSV to exercise error handling,
    // and test aggregation logic with an empty list.

    @IsTest
    static void testBlankCsvReturnsError() {
        PPIA_QueryCareEpisodes.EpisodeRequest req = new PPIA_QueryCareEpisodes.EpisodeRequest();
        req.patientAccountIdsCsv = '';
        req.limitCount = 100;

        Test.startTest();
        List<PPIA_QueryCareEpisodes.EpisodeResult> results =
            PPIA_QueryCareEpisodes.queryEpisodes(
                new List<PPIA_QueryCareEpisodes.EpisodeRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 result');
        System.assertEquals(false, results[0].success, 'Should fail with blank CSV');
        System.assertNotEquals(null, results[0].errorMessage, 'Error message should be set');
    }

    @IsTest
    static void testAggregateEmptyList() {
        List<SObject> emptyList = new List<SObject>();

        Test.startTest();
        PPIA_QueryCareEpisodes.EpisodeResult res =
            PPIA_QueryCareEpisodes.aggregateEpisodes(emptyList);
        Test.stopTest();

        System.assertEquals(0,    res.totalEpisodes,   'Total episodes should be 0');
        System.assertEquals(0,    res.episodesT12M,    'T12M should be 0');
        System.assertEquals(0,    res.episodesT90D,    'T90D should be 0');
        System.assertEquals(0,    res.paApprovedCount, 'PA approved should be 0');
        System.assertEquals(0,    res.paDeniedCount,   'PA denied should be 0');
        System.assertEquals(0.0,  res.collectionRate,  'Collection rate should be 0');
        System.assertEquals(0.0,  res.totalBilled,     'Total billed should be 0');
        System.assertEquals(0.0,  res.totalReceived,   'Total received should be 0');
    }

    @IsTest
    static void testInvocableWithValidCsvHandlesGracefully() {
        // Uses a dummy Account ID — ssot__Opportunity__dlm will return 0 rows
        // This tests the invocable end-to-end including the SOQL path
        PPIA_QueryCareEpisodes.EpisodeRequest req = new PPIA_QueryCareEpisodes.EpisodeRequest();
        req.patientAccountIdsCsv = '001000000000001AAA';
        req.limitCount = 10;

        Test.startTest();
        List<PPIA_QueryCareEpisodes.EpisodeResult> results =
            PPIA_QueryCareEpisodes.queryEpisodes(
                new List<PPIA_QueryCareEpisodes.EpisodeRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return 1 result');
        // Either succeeds with 0 episodes or fails gracefully if object not available
        if (results[0].success) {
            System.assertEquals(0, results[0].totalEpisodes, 'No episodes for dummy ID');
        } else {
            System.assertNotEquals(null, results[0].errorMessage, 'Error message should be set');
        }
    }

    @IsTest
    static void testMultipleRequestsInBulk() {
        PPIA_QueryCareEpisodes.EpisodeRequest req1 = new PPIA_QueryCareEpisodes.EpisodeRequest();
        req1.patientAccountIdsCsv = '001000000000001AAA';

        PPIA_QueryCareEpisodes.EpisodeRequest req2 = new PPIA_QueryCareEpisodes.EpisodeRequest();
        req2.patientAccountIdsCsv = '';

        Test.startTest();
        List<PPIA_QueryCareEpisodes.EpisodeResult> results =
            PPIA_QueryCareEpisodes.queryEpisodes(
                new List<PPIA_QueryCareEpisodes.EpisodeRequest>{ req1, req2 }
            );
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should return 2 results for 2 requests');
        System.assertEquals(false, results[1].success, 'Second request should fail (blank CSV)');
    }
}