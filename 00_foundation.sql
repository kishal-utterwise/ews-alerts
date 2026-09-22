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

INSERT INTO "FRM_ALERT_HIERARCHY" (id, name, description, "approvalFlowsJson", "isDeleted", "isScrollPending", "createdAt", "updatedAt")
VALUES (1, 'Test Hierarchy', 'seed for EWS rule testing', NULL, false, false, now(), now())
ON CONFLICT DO NOTHING;

INSERT INTO "USER" (id, "userId", "userName", "firstName", "lastName", "branch_Id", status)
VALUES (1, 'testuser1', 'Test User', 'Test', 'User', 201, 'ACTIVE')
ON CONFLICT DO NOTHING;

COMMIT;
