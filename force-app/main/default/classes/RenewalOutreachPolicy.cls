/**
 * UC-LIF-06 outreach constants and stage resolution.
 */
public with sharing class RenewalOutreachPolicy {
    public static final String STAGE_T60 = 'T60';
    public static final String STAGE_T30 = 'T30';
    public static final String STAGE_T7 = 'T7';
    public static final List<String> STAGES = new List<String>{
        STAGE_T60,
        STAGE_T30,
        STAGE_T7
    };

    public static String stage(Date renewalDate, Date today) {
        if (renewalDate == null || today == null || renewalDate < today) {
            return null;
        }
        Integer days = today.daysBetween(renewalDate);
        if (days > 30 && days <= 60) {
            return STAGE_T60;
        }
        if (days > 7 && days <= 30) {
            return STAGE_T30;
        }
        if (days <= 7) {
            return STAGE_T7;
        }
        return null;
    }

    public static String subjectPrefix(String stage) {
        if (stage == STAGE_T60) {
            return 'Renewal T-60';
        }
        if (stage == STAGE_T30) {
            return 'Renewal T-30';
        }
        return 'Renewal T-7';
    }

    public static String subject(String stage, Boolean doNotCall) {
        String suffix = doNotCall == true ? ' Email only (DNC)' : '';
        if (stage == STAGE_T60) {
            return 'Renewal T-60 - Outreach' + suffix;
        }
        if (stage == STAGE_T30) {
            return 'Renewal T-30 - Offer' + suffix;
        }
        return 'Renewal T-7 - Escalation' + suffix;
    }

    public static String description(String stage, Boolean doNotCall) {
        String contactMode = doNotCall == true
            ? 'Email only. Do Not Call is set; no phone contact is permitted.'
            : 'Advisor outreach permitted by phone.';
        if (stage == STAGE_T60) {
            return 'First renewal outreach. ' + contactMode;
        }
        if (stage == STAGE_T30) {
            return 'Renewal offer to be prepared and presented. ' + contactMode;
        }
        return 'Final renewal outreach and advisor escalation. ' + contactMode;
    }

    public static String key(Id engagementId, String stage) {
        return String.valueOf(engagementId) + ':' + stage;
    }
}
