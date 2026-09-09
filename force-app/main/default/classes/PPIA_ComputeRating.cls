/**
 * PPIA_ComputeRating
 * Invocable Apex class that applies the MIMIT Rating Engine to produce
 * a composite 0–100 score and 1–5 star rating for a Purchaser Plan.
 *
 * Dimension weights:
 *   Collection Rate  30%  — benchmark: 85% collection = 100 pts
 *   PA Friction      25%  — benchmark: 90% approval   = 100 pts
 *   Volume & Growth  15%  — subjective: 5+ members, growing
 *   Payment Speed    15%  — benchmark: TAT < 15 days
 *   Clinical Mix     15%  — PAD/SVD coverage strength
 *
 * Star thresholds: 80–100=5★  65–79=4★  50–64=3★  35–49=2★  0–34=1★
 */
public with sharing class PPIA_ComputeRating {

    // ─── Request / Result wrappers ───────────────────────────────────────────

    public class RatingRequest {
        @InvocableVariable(label='Collection Rate %' required=true)
        public Decimal collectionRate;

        @InvocableVariable(label='PA Approval Rate %' required=true)
        public Decimal paApprovalRate;

        @InvocableVariable(label='Active Member Count' required=true)
        public Integer memberCount;

        @InvocableVariable(label='Episodes T12M' required=true)
        public Integer episodesT12M;

        @InvocableVariable(label='Payment Speed Score (0–100)' required=false)
        public Decimal paymentSpeedScore;

        @InvocableVariable(label='Clinical Mix Score (0–100)' required=false)
        public Decimal clinicalMixScore;
    }

    public class DimensionScore {
        @InvocableVariable public String dimensionName;
        @InvocableVariable public Decimal score;
        @InvocableVariable public Decimal weight;
        @InvocableVariable public Decimal weightedScore;
        @InvocableVariable public String benchmark;
    }

    public class RatingResult {
        @InvocableVariable public Decimal compositeScore;
        @InvocableVariable public Integer starRating;
        @InvocableVariable public String  starLabel;
        @InvocableVariable public String  ratingRationale;
        @InvocableVariable public Decimal scoreCollection;
        @InvocableVariable public Decimal scorePA;
        @InvocableVariable public Decimal scoreVolume;
        @InvocableVariable public Decimal scorePayment;
        @InvocableVariable public Decimal scoreClinical;
        @InvocableVariable public Boolean success;
        @InvocableVariable public String  errorMessage;
    }

    // ─── Invocable entry point ───────────────────────────────────────────────

    @InvocableMethod(
        label='PPIA Compute Rating'
        description='Applies the MIMIT Rating Engine to compute a composite 0–100 score and 1–5 star rating for a Purchaser Plan.'
    )
    public static List<RatingResult> computeRating(List<RatingRequest> requests) {
        List<RatingResult> results = new List<RatingResult>();
        for (RatingRequest req : requests) {
            results.add(processRequest(req));
        }
        return results;
    }

    // ─── Core rating logic ───────────────────────────────────────────────────

    @TestVisible
    private static RatingResult processRequest(RatingRequest req) {
        RatingResult res = new RatingResult();

        try {
            // --- Dimension 1: Collection Rate (30%) ---
            // 85% collection = 100 pts; scales linearly
            Decimal collectionScore = Math.min(100,
                (req.collectionRate / 85 * 100)).setScale(1);

            // --- Dimension 2: PA Friction (25%) ---
            // 90% approval = ~100 pts (multiply by 0.85 to compress scale)
            // Formula from spec: min(100, paApprovalRate * 0.85) * 0.25
            // Note: this maps 90% → 76.5 raw → weighted, intentional per spec
            Decimal paScore = Math.min(100,
                (req.paApprovalRate * 0.85)).setScale(1);

            // --- Dimension 3: Volume & Growth (15%) ---
            Decimal volumeScore = computeVolumeScore(req.memberCount, req.episodesT12M);

            // --- Dimension 4: Payment Speed (15%) ---
            // Passed in from caller (default 60 if not provided)
            Decimal paymentScore = (req.paymentSpeedScore != null && req.paymentSpeedScore >= 0)
                ? Math.min(100, req.paymentSpeedScore)
                : 60;

            // --- Dimension 5: Clinical Mix (15%) ---
            // Passed in from caller (default 75 if not provided)
            Decimal clinicalScore = (req.clinicalMixScore != null && req.clinicalMixScore >= 0)
                ? Math.min(100, req.clinicalMixScore)
                : 75;

            // --- Composite score ---
            Decimal composite =
                (collectionScore * 0.30) +
                (paScore         * 0.25) +
                (volumeScore     * 0.15) +
                (paymentScore    * 0.15) +
                (clinicalScore   * 0.15);
            composite = composite.setScale(1);

            // --- Star rating ---
            Integer stars = starsFromScore(composite);
            String  label = labelFromStars(stars);

            // --- Build rationale string ---
            String rationale = buildRationale(
                collectionScore, paScore, volumeScore, paymentScore, clinicalScore,
                req.collectionRate, req.paApprovalRate, req.memberCount, req.episodesT12M
            );

            // --- Populate result ---
            res.compositeScore   = composite;
            res.starRating       = stars;
            res.starLabel        = label;
            res.ratingRationale  = rationale;
            res.scoreCollection  = collectionScore;
            res.scorePA          = paScore;
            res.scoreVolume      = volumeScore;
            res.scorePayment     = paymentScore;
            res.scoreClinical    = clinicalScore;
            res.success          = true;

        } catch (Exception e) {
            res.success      = false;
            res.errorMessage = e.getMessage();
        }

        return res;
    }

    // ─── Volume score helper ─────────────────────────────────────────────────

    @TestVisible
    private static Decimal computeVolumeScore(Integer memberCount, Integer episodesT12M) {
        Decimal score = 0;

        // Member score: 5+ members = 50 pts, scales 0–5
        Decimal memberScore = (memberCount != null && memberCount > 0)
            ? Math.min(50, ((Decimal) memberCount / 5 * 50))
            : 0;

        // Episode score: 50+ episodes T12M = 50 pts, scales 0–50
        Decimal episodeScore = (episodesT12M != null && episodesT12M > 0)
            ? Math.min(50, ((Decimal) episodesT12M / 50 * 50))
            : 0;

        score = (memberScore + episodeScore).setScale(1);
        return Math.min(100, score);
    }

    // ─── Star rating helpers ─────────────────────────────────────────────────

    @TestVisible
    private static Integer starsFromScore(Decimal score) {
        if (score >= 80) return 5;
        if (score >= 65) return 4;
        if (score >= 50) return 3;
        if (score >= 35) return 2;
        return 1;
    }

    @TestVisible
    private static String labelFromStars(Integer stars) {
        if (stars == 5) return 'Excellent — Preferred Payer';
        if (stars == 4) return 'Good — Favorable Payer';
        if (stars == 3) return 'Satisfactory — Average Payer';
        if (stars == 2) return 'Poor — Issues Noted';
        return 'Avoid — Significant Problems';
    }

    // ─── Rationale builder ───────────────────────────────────────────────────

    private static String buildRationale(
        Decimal colScore, Decimal paScore, Decimal volScore,
        Decimal payScore, Decimal clinScore,
        Decimal collectionRate, Decimal paApprovalRate,
        Integer memberCount, Integer episodesT12M
    ) {
        return
            'Collection Rate: ' + collectionRate + '% → Score: ' + colScore + '/100 (wt 30%) | ' +
            'PA Approval: ' + paApprovalRate + '% → Score: ' + paScore + '/100 (wt 25%) | ' +
            'Volume: ' + memberCount + ' members, ' + episodesT12M + ' eps T12M → Score: ' + volScore + '/100 (wt 15%) | ' +
            'Payment Speed → Score: ' + payScore + '/100 (wt 15%) | ' +
            'Clinical Mix → Score: ' + clinScore + '/100 (wt 15%)';
    }
}