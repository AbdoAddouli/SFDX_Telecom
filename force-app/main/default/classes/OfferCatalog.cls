/**
 * Resolves the selected plan and device from the catalogue and applies fibre
 * eligibility. This class is read-only; pricing remains in PricingService.
 */
public with sharing class OfferCatalog {
    private static final String PLAN_TYPE_FIBER = 'Fiber';

    public CatalogQueryService.ProductView plan;
    public CatalogQueryService.ProductView device;
    public Boolean fiber;

    public static OfferCatalog resolve(OfferContext context) {
        if (context.selection.planProductId == null) {
            throw new OfferBuilderService.OfferException(
                'Plan product is required.'
            );
        }

        OfferCatalog catalog = new OfferCatalog();
        catalog.plan = findView(
            CatalogQueryService.getPlans(
                context.offerType,
                context.commitmentCode
            ),
            context.selection.planProductId
        );
        if (catalog.plan == null) {
            throw new OfferBuilderService.OfferException(
                'The selected plan is not available for ' + context.offerType +
                ' with commitment ' + context.commitmentCode + '.'
            );
        }
        if (catalog.plan.requiresCommitment == true
            && PricingScope.NO_COMMITMENT.equals(context.commitmentCode)) {
            throw new OfferBuilderService.OfferException(
                'The selected plan requires a commitment option.'
            );
        }

        if (context.selection.deviceProductId != null) {
            catalog.device = findView(
                CatalogQueryService.getDevices(),
                context.selection.deviceProductId
            );
            if (catalog.device == null) {
                throw new OfferBuilderService.OfferException(
                    'The selected device is not available.'
                );
            }
        }

        catalog.fiber = PLAN_TYPE_FIBER.equalsIgnoreCase(catalog.plan.planType);
        if (catalog.fiber) {
            validateFiber(context, catalog.plan);
        }
        return catalog;
    }

    private static void validateFiber(
        OfferContext context,
        CatalogQueryService.ProductView plan
    ) {
        String postalCode = context.selection.postalCode;
        if (String.isBlank(postalCode)) {
            throw new OfferBuilderService.OfferException(
                'Postal code is required to validate fibre eligibility.'
            );
        }

        List<CatalogQueryService.ProductView> eligible =
            CatalogQueryService.filterByEligibility(
                new List<CatalogQueryService.ProductView>{ plan },
                postalCode
            );
        if (eligible == null || eligible.isEmpty()) {
            throw new OfferBuilderService.OfferException(
                'The selected fibre plan is not available at postal code ' +
                postalCode.trim() + '.'
            );
        }
        CatalogQueryService.ProductView eligiblePlan = eligible[0];
        if (eligiblePlan.activationBlocked == true) {
            throw new OfferBuilderService.OfferException(
                'Fibre activation is not available at postal code ' +
                postalCode.trim() + ' until ' +
                eligiblePlan.earliestActivationDate + '.'
            );
        }
    }

    private static CatalogQueryService.ProductView findView(
        List<CatalogQueryService.ProductView> views,
        Id productId
    ) {
        if (views == null) {
            return null;
        }
        for (CatalogQueryService.ProductView view : views) {
            if (view != null && view.productId == productId) {
                return view;
            }
        }
        return null;
    }
}
