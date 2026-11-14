/**
 * Pure activation rules and the per-order-item working context.
 *
 * This class contains no SOQL or DML: it normalizes product/commitment data and
 * answers the small questions the reader, provisioner, and service need.
 */
public with sharing class ActivationContext {
    private static final Set<String> COMMITMENT_CODES = new Set<String>{
        'NOCOMMIT',
        'COMMIT12',
        'COMMIT24'
    };
    private static final Map<String, Integer> COMMITMENT_MONTHS =
        new Map<String, Integer>{
            'COMMIT12' => 12,
            'COMMIT24' => 24
        };
    private static final Set<String> SERVICE_LINE_TYPES = new Set<String>{
        'Mobile',
        'Fiber',
        'Landline',
        'Device'
    };

    public class ItemContext {
        public OrderItem item;
        public Product2 product;
        public String commitmentCode;
        public Integer durationMonths;
        public String serviceLineType;
        public Boolean isRecurring;
        public Boolean isDevice;
        public Asset asset;
        public Subscription__c subscription;
        public Engagement__c engagement;
        public Engagement__c rootEngagement;
        public Subscription__c parentSubscription;
    }

    public static ItemContext build(
        OrderItem item,
        Product2 product,
        Subscription__c subscription,
        Engagement__c engagement,
        Asset asset
    ) {
        ItemContext context = new ItemContext();
        context.item = item;
        context.product = product;
        context.commitmentCode = normalizeCommitment(
            item.Commitment_Option_Code__c
        );
        context.durationMonths = commitmentMonths(context.commitmentCode);
        context.serviceLineType = serviceLineType(product);
        context.isRecurring = product.Recurring__c == true;
        context.isDevice = context.serviceLineType == 'Device';
        context.subscription = subscription;
        context.engagement = engagement;
        context.asset = asset;
        return context;
    }

    public static String normalizeCommitment(String rawCode) {
        String code = String.isBlank(rawCode)
            ? 'NOCOMMIT'
            : rawCode.trim().toUpperCase();
        if (!COMMITMENT_CODES.contains(code)) {
            throw new ActivationException(
                'Unsupported commitment option code: ' + rawCode
            );
        }
        return code;
    }

    public static Integer commitmentMonths(String code) {
        return COMMITMENT_MONTHS.get(code);
    }

    public static String serviceLineType(Product2 product) {
        if (product == null) {
            throw new ActivationException(
                'A product is required to determine the service line type.'
            );
        }
        String candidate = product.Plan_Type__c;
        if (String.isBlank(candidate) && product.Family != null) {
            if (product.Family.containsIgnoreCase('DEVICE')) {
                candidate = 'Device';
            } else if (product.Family.containsIgnoreCase('FIBER')) {
                candidate = 'Fiber';
            } else if (product.Family.containsIgnoreCase('MOBILE')) {
                candidate = 'Mobile';
            }
        }
        if (
            String.isBlank(candidate) ||
            !SERVICE_LINE_TYPES.contains(candidate)
        ) {
            throw new ActivationException(
                'The product does not map to a valid service line type.'
            );
        }
        return candidate;
    }

    public static String engagementKey(Id orderItemId) {
        return 'ENG-' + String.valueOf(orderItemId);
    }

    public static Integer maxTerm(List<ItemContext> contexts) {
        Integer maximum = 0;
        for (ItemContext context : contexts) {
            if (
                context.durationMonths != null &&
                context.durationMonths > maximum
            ) {
                maximum = context.durationMonths;
            }
        }
        return maximum;
    }

    public static String contractType(List<ItemContext> contexts) {
        Boolean mobile = false;
        Boolean fiber = false;
        for (ItemContext context : contexts) {
            if (context.serviceLineType == 'Mobile') {
                mobile = true;
            } else if (
                context.serviceLineType == 'Fiber' ||
                context.serviceLineType == 'Landline'
            ) {
                fiber = true;
            }
        }
        if (mobile && fiber) {
            return 'Bundle';
        }
        if (fiber) {
            return 'Fiber';
        }
        if (mobile) {
            return 'Mobile';
        }
        return null;
    }

    public static ItemContext primaryPlan(List<ItemContext> contexts) {
        for (ItemContext context : contexts) {
            if (context.isRecurring) {
                return context;
            }
        }
        return null;
    }

    public static ItemContext parentPlan(
        List<ItemContext> contexts,
        ItemContext device
    ) {
        Integer deviceIndex = contexts.indexOf(device);
        for (Integer index = deviceIndex - 1; index >= 0; index--) {
            if (contexts[index].isRecurring) {
                return contexts[index];
            }
        }
        for (ItemContext context : contexts) {
            if (context.isRecurring) {
                return context;
            }
        }
        return null;
    }

    public static Integer countAssets(List<ItemContext> contexts) {
        Integer count = 0;
        for (ItemContext context : contexts) {
            if (context.asset != null) {
                count++;
            }
        }
        return count;
    }

    public static Integer countSubscriptions(List<ItemContext> contexts) {
        Integer count = 0;
        for (ItemContext context : contexts) {
            if (context.subscription != null) {
                count++;
            }
        }
        return count;
    }

    public static Integer countEngagements(List<ItemContext> contexts) {
        Set<Id> engagementIds = new Set<Id>();
        for (ItemContext context : contexts) {
            if (context.engagement != null) {
                engagementIds.add(context.engagement.Id);
            }
        }
        return engagementIds.size();
    }
}
