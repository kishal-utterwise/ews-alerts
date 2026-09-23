BEGIN;

INSERT INTO "GENERAL_LEDGER" ("id","accountHead","accruedAccountHead","bankName","shortName","isDeleted","mapGl","isScrollPending")
VALUES (71, 19, 71, 'GL ACCOUNT 71', 'GL71', false, false, false)
ON CONFLICT DO NOTHING;

INSERT INTO "ACCOUNT" ("id","generalLedger_Id","accountCode","accountNumber","branch_Id","currentStatus","dateOfOpening","actualBalance","shadowBalance")
VALUES (31, 71, 'AC31', 'ACC31', 201, 1, (CURRENT_DATE - INTERVAL '1 month')::date, 0, 0)
ON CONFLICT DO NOTHING;

INSERT INTO "CUSTOMER_DETAILS" ("id","isIndividual","ucic","rekycDueOn","branchId","status")
VALUES (31, true, 'UCIC31', now() + interval '1 year', 201, 'ACTIVE')
ON CONFLICT DO NOTHING;

INSERT INTO "ACCOUNT_CUSTOMER" ("id","account_Id","customer_Id","customerAccountRelationshipType")
VALUES (31, 31, 31, 0)
ON CONFLICT DO NOTHING;

-- Shared by "Default In SMA1" and "Quick SMA" - one row, on account 31, so a single account
-- satisfies both conditions at once (needed when the app combines them into one AND/OR rule,
-- not just when each is tested as its own separate rule). snapShotDate = today lands inside
-- BOTH functions' windows: DefaultInPaymentForSMAInLastNTimes's 4-month window (current month
-- + 3 back) and QuickSMAInLastNMonths's stricter current-month-only window. defaultDate 45 days
-- back classifies as SMA1, which both functions accept.
INSERT INTO "SMA_LOG" (id, "account_Id", "snapShotDate", "defaultDate", "overdueAmount", "createdAt")
SELECT 201, 31, CURRENT_DATE, (CURRENT_DATE - INTERVAL '45 days')::date, 5000, now()
ON CONFLICT DO NOTHING;

INSERT INTO "FRM_ALERT_HIERARCHY" (id, name, description, "approvalFlowsJson", "isDeleted", "isScrollPending", "createdAt", "updatedAt")
VALUES (1, 'Test Hierarchy', 'seed for EWS rule testing', NULL, false, false, now(), now())
ON CONFLICT DO NOTHING;

INSERT INTO "USER" (id, "userId", "userName", "firstName", "lastName", "branch_Id", status)
VALUES (1, 'testuser1', 'Test User', 'Test', 'User', 201, 'ACTIVE')
ON CONFLICT DO NOTHING;

COMMIT;
