BEGIN;

-- Quick SMA needs its own account (not 31, which Default In SMA1 already owns) and its own
-- recent snapshot:
--  - QuickSMAInLastNMonths() groups DefaultInPaymentForSMAInLastNTimes-style logic per account_Id
--    and only looks at the LATEST snapShotDate row for that account - sharing account 31 meant
--    only one of the two rules' SMA_LOG rows ever actually got evaluated.
--  - QuickSMAInLastNMonths() also restricts snapShotDate to ONLY the current evaluation month
--    (1st to last day) - the old snapShotDate (last day of the PREVIOUS month) never matched.
--  - It additionally requires ACCOUNT.dateOfOpening within the LastNMonths window (a "quickly"
--    opened account), hence the new account below opened 10 days ago.
INSERT INTO "ACCOUNT" ("id","generalLedger_Id","accountCode","accountNumber","branch_Id","currentStatus","dateOfOpening","actualBalance","shadowBalance")
VALUES (32, 71, 'AC32', 'ACC32', 201, 1, (CURRENT_DATE - INTERVAL '10 days')::date, 0, 0)
ON CONFLICT DO NOTHING;

INSERT INTO "CUSTOMER_DETAILS" ("id","isIndividual","ucic","rekycDueOn","branchId","status")
VALUES (32, true, 'UCIC32', now() + interval '1 year', 201, 'ACTIVE')
ON CONFLICT DO NOTHING;

INSERT INTO "ACCOUNT_CUSTOMER" ("id","account_Id","customer_Id","customerAccountRelationshipType")
VALUES (32, 32, 32, 0)
ON CONFLICT DO NOTHING;

INSERT INTO "SMA_LOG" (id, "account_Id", "snapShotDate", "defaultDate", "overdueAmount", "createdAt")
SELECT 202, 32, CURRENT_DATE, (CURRENT_DATE - INTERVAL '45 days')::date, 5000, now()
ON CONFLICT DO NOTHING;

INSERT INTO "FRM_RULE" (id, name, code, description, "ruleType", "startDate", "endDate", "jsonString", status,
                        "alertGenerationToClassificationTat", "alertActions", "ruleSeverity", "alertHierarchy_Id",
                        "alertHierarchyJson", "createdBy_Id", "updatedBy_Id", "createdAt", "updatedAt", "isDeleted", "versionNo",
                        "isScrollPending", "scrollId")
VALUES
(504, 'Quick SMA (Test)', 'EWS-QSMA-TEST',
 'Recently opened account already at SMA1/SMA2, over last N months', 2, CURRENT_DATE, (CURRENT_DATE + INTERVAL '5 years')::date,
 $j$
 {"name":"Quick SMA (Test)","code":"EWS-QSMA-TEST","ruleType":"EWS_BASED","alertHierarchyId":1,
  "ruleSeverity":"MEDIUM","alertGenerationToClassificationTat":7,"action":[],
  "topCondition":"AND",
  "conditions":[{"Order":1,"name":"Quick SMA",
   "function":"quickSMAInLastNMonths","isAdvanceField":true,
   "parameters":[{"name":"LastNMonths","value":"3","type":"number"}],"relation":">=","value":"1","type":"number"}]}
 $j$, 1, 7, '[]', 1, 1, NULL, 1, 1, now(), now(), false, 1, false, NULL)
ON CONFLICT DO NOTHING;

INSERT INTO "FRM_RULE_HISTORY" (id, "frmRule_Id", "versionNo", name, code, description, "ruleType",
                                 "effectiveFrom", "startDate", "endDate", "jsonString",
                                 "alertGenerationToClassificationTat", "alertActions", "ruleSeverity",
                                 "createdBy_Id", "updatedBy_Id", "createdAt", "updatedAt", "isDeleted")
SELECT r.id + 100, r.id, r."versionNo", r.name, r.code, r.description, r."ruleType",
       CURRENT_DATE, r."startDate", r."endDate", r."jsonString",
       r."alertGenerationToClassificationTat", r."alertActions", r."ruleSeverity",
       r."createdBy_Id", r."updatedBy_Id", now(), now(), false
FROM "FRM_RULE" r WHERE r.id = 504
ON CONFLICT DO NOTHING;

COMMIT;
