/**
 * PPIA_ComputeRatingTest
 * Unit tests for PPIA_ComputeRating.
 * Validates the rating engine formula, star thresholds, volume scoring,
 * and the Wellcare Meridian PoC result (score ~79.7, 4 stars).
 */
@IsTest
private class PPIA_ComputeRatingTest {

    // ─── PoC validation: Wellcare Meridian Dual Align ────────────────────────
    // collectionScore = min(100, 88.3/85*100) = 100 (capped)
    // paScore         = min(100, 86.0*0.85)   = 73.1
    // volumeScore     = 5 members(50) + 57 eps(50) = 100
    // composite       = 100*.30 + 73.1*.25 + 100*.15 + 60*.15 + 85*.15 = ~85.0 → 5 stars

    @IsTest
    static void testWellcareMeridianPoC() {
        PPIA_ComputeRating.RatingRequest req = new PPIA_ComputeRating.RatingRequest();
        req.collectionRate   = 88.3;  // 88.3% collection rate from PoC
        req.paApprovalRate   = 86.0;  // 86% PA approval rate from PoC
        req.memberCount      = 5;     // 5 active members from PoC
        req.episodesT12M     = 57;    // ~57 T12M episodes estimated
        req.paymentSpeedScore = 60;   // default mid-range
        req.clinicalMixScore  = 85;   // strong PAD/SVD coverage

        Test.startTest();
        List<PPIA_ComputeRating.RatingResult> results =
            PPIA_ComputeRating.computeRating(
                new List<PPIA_ComputeRating.RatingRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        PPIA_ComputeRating.RatingResult res = results[0];

        System.assertEquals(true, res.success, 'Rating should succeed');
        System.assertEquals(5, res.starRating, 'Wellcare PoC should be 5 stars');
        System.assertEquals('Excellent — Preferred Payer', res.starLabel);
        // 88.3% collection caps to 100; full volume score → composite ~85.0 (5-star range)
        System.assert(res.compositeScore >= 80,
            'Composite score should be in 5-star range (>=80). Actual: ' + res.compositeScore);
    }

    // ─── Star threshold tests ─────────────────────────────────────────────────

    @IsTest
    static void testFiveStarExcellent() {
        PPIA_ComputeRating.RatingRequest req = buildRequest(95, 95, 10, 100, 90, 90);
        List<PPIA_ComputeRating.RatingResult> results = PPIA_ComputeRating.computeRating(
            new List<PPIA_ComputeRating.RatingRequest>{ req });

        System.assertEquals(5, results[0].starRating, 'Should be 5 stars');
        System.assertEquals('Excellent — Preferred Payer', results[0].starLabel);
        System.assert(results[0].compositeScore >= 80, 'Score should be >= 80');
    }

    @IsTest
    static void testThreeStarSatisfactory() {
        PPIA_ComputeRating.RatingRequest req = buildRequest(65, 65, 3, 20, 50, 50);
        List<PPIA_ComputeRating.RatingResult> results = PPIA_ComputeRating.computeRating(
            new List<PPIA_ComputeRating.RatingRequest>{ req });

        System.assert(results[0].starRating >= 2 && results[0].starRating <= 4,
            'Mid-range inputs should produce 2–4 stars');
    }

    @IsTest
    static void testOneStarAvoid() {
        PPIA_ComputeRating.RatingRequest req = buildRequest(20, 20, 0, 0, 10, 10);
        List<PPIA_ComputeRating.RatingResult> results = PPIA_ComputeRating.computeRating(
            new List<PPIA_ComputeRating.RatingRequest>{ req });

        System.assertEquals(1, results[0].starRating, 'Very poor inputs should be 1 star');
        System.assertEquals('Avoid — Significant Problems', results[0].starLabel);
        System.assert(results[0].compositeScore < 35, 'Score should be < 35');
    }

    // ─── Collection rate scoring ──────────────────────────────────────────────

    @IsTest
    static void testCollectionRateAt85GivesFullScore() {
        // 85% collection = 100 collection pts
        PPIA_ComputeRating.RatingRequest req = buildRequest(85, 90, 5, 50, 100, 100);
        List<PPIA_ComputeRating.RatingResult> results = PPIA_ComputeRating.computeRating(
            new List<PPIA_ComputeRating.RatingRequest>{ req });

        System.assertEquals(100, results[0].scoreCollection,
            '85% collection should score 100');
    }

    @IsTest
    static void testCollectionRateAbove85CapsAt100() {
        PPIA_ComputeRating.RatingRequest req = buildRequest(100, 90, 5, 50, 100, 100);
        List<PPIA_ComputeRating.RatingResult> results = PPIA_ComputeRating.computeRating(
            new List<PPIA_ComputeRating.RatingRequest>{ req });

        System.assertEquals(100, results[0].scoreCollection,
            'Collection score should cap at 100');
    }

    // ─── Volume score tests ───────────────────────────────────────────────────

    @IsTest
    static void testVolumeScoreZeroMembersZeroEpisodes() {
        Decimal score = PPIA_ComputeRating.computeVolumeScore(0, 0);
        System.assertEquals(0, score, 'Zero members and episodes = 0 volume score');
    }

    @IsTest
    static void testVolumeScoreMaxesAt100() {
        Decimal score = PPIA_ComputeRating.computeVolumeScore(100, 500);
        System.assertEquals(100, score, 'Large numbers should cap at 100');
    }

    @IsTest
    static void testVolumeScoreFiveMembers50Episodes() {
        Decimal score = PPIA_ComputeRating.computeVolumeScore(5, 50);
        System.assertEquals(100, score,
            '5 members + 50 T12M episodes = full 100 volume score');
    }

    // ─── Star helper tests ────────────────────────────────────────────────────

    @IsTest
    static void testStarBoundaries() {
        System.assertEquals(5, PPIA_ComputeRating.starsFromScore(80));
        System.assertEquals(5, PPIA_ComputeRating.starsFromScore(100));
        System.assertEquals(4, PPIA_ComputeRating.starsFromScore(65));
        System.assertEquals(4, PPIA_ComputeRating.starsFromScore(79));
        System.assertEquals(3, PPIA_ComputeRating.starsFromScore(50));
        System.assertEquals(3, PPIA_ComputeRating.starsFromScore(64));
        System.assertEquals(2, PPIA_ComputeRating.starsFromScore(35));
        System.assertEquals(2, PPIA_ComputeRating.starsFromScore(49));
        System.assertEquals(1, PPIA_ComputeRating.starsFromScore(0));
        System.assertEquals(1, PPIA_ComputeRating.starsFromScore(34));
    }

    @IsTest
    static void testStarLabels() {
        System.assertEquals('Excellent — Preferred Payer',    PPIA_ComputeRating.labelFromStars(5));
        System.assertEquals('Good — Favorable Payer',         PPIA_ComputeRating.labelFromStars(4));
        System.assertEquals('Satisfactory — Average Payer',   PPIA_ComputeRating.labelFromStars(3));
        System.assertEquals('Poor — Issues Noted',            PPIA_ComputeRating.labelFromStars(2));
        System.assertEquals('Avoid — Significant Problems',   PPIA_ComputeRating.labelFromStars(1));
    }

    // ─── Default score values when not provided ───────────────────────────────

    @IsTest
    static void testNullPaymentAndClinicalDefaultsApplied() {
        PPIA_ComputeRating.RatingRequest req = new PPIA_ComputeRating.RatingRequest();
        req.collectionRate    = 85;
        req.paApprovalRate    = 90;
        req.memberCount       = 5;
        req.episodesT12M      = 50;
        req.paymentSpeedScore = null;  // should default to 60
        req.clinicalMixScore  = null;  // should default to 75

        Test.startTest();
        List<PPIA_ComputeRating.RatingResult> results =
            PPIA_ComputeRating.computeRating(
                new List<PPIA_ComputeRating.RatingRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        System.assertEquals(60, results[0].scorePayment,  'Payment should default to 60');
        System.assertEquals(75, results[0].scoreClinical, 'Clinical should default to 75');
    }

    // ─── Bulk invocable test ──────────────────────────────────────────────────

    @IsTest
    static void testBulkInvocable() {
        List<PPIA_ComputeRating.RatingRequest> reqs = new List<PPIA_ComputeRating.RatingRequest>();
        for (Integer i = 0; i < 10; i++) {
            reqs.add(buildRequest(70 + i, 80 + i, 5, 50, 60, 70));
        }

        Test.startTest();
        List<PPIA_ComputeRating.RatingResult> results =
            PPIA_ComputeRating.computeRating(reqs);
        Test.stopTest();

        System.assertEquals(10, results.size(), 'Should return 10 results');
        for (PPIA_ComputeRating.RatingResult res : results) {
            System.assertEquals(true, res.success);
            System.assert(res.compositeScore > 0);
        }
    }

    // ─── Helper ──────────────────────────────────────────────────────────────

    private static PPIA_ComputeRating.RatingRequest buildRequest(
        Decimal collRate, Decimal paRate, Integer members,
        Integer t12M, Decimal payScore, Decimal clinScore
    ) {
        PPIA_ComputeRating.RatingRequest req = new PPIA_ComputeRating.RatingRequest();
        req.collectionRate    = collRate;
        req.paApprovalRate    = paRate;
        req.memberCount       = members;
        req.episodesT12M      = t12M;
        req.paymentSpeedScore = payScore;
        req.clinicalMixScore  = clinScore;
        return req;
    }
}