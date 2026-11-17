/**
 * Cancellation business constants. Keeping these in one place makes the
 * 30-day notice rule and request lifecycle states consistent across helpers.
 */
public with sharing class CancellationPolicy {
    public static final Integer NOTICE_DAYS = 30;
    public static final String REQUEST_TYPE = 'Cancellation';
    public static final String STATUS_AWAITING = 'Awaiting_Approval';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_IN_FULFILMENT = 'In_Fulfilment';
    public static final String STATUS_COMPLETED = 'Completed';

    public static final Set<String> VALID_REASONS = new Set<String>{
        'Price',
        'Coverage',
        'Service_Quality',
        'Moving',
        'Competitor',
        'Other'
    };

    public static final Set<String> IN_FLIGHT_STATUSES = new Set<String>{
        STATUS_APPROVED,
        STATUS_AWAITING,
        STATUS_IN_FULFILMENT
    };

    public static Date earliestEffectiveDate(Date today) {
        return today.addDays(NOTICE_DAYS);
    }
}
