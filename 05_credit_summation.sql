BEGIN;

INSERT INTO "LOAN_ACCOUNT" (id, "account_Id", status, "sanctionAmount")
VALUES (31, 31, 0, 100000)
ON CONFLICT DO NOTHING;

INSERT INTO "TRANSACTIONS" (id, type, category, amount, "runningBalance", "transactionDateTime", "valueDateTime", "account_Id", "customer_Id", "branch_Id", status)
SELECT 311, 0, 0, 100000::numeric, 0::numeric, (CURRENT_DATE - INTERVAL '20 days'), (CURRENT_DATE - INTERVAL '20 days'), 31, 31, 201, 'SUCCESS' UNION ALL
SELECT 312, 0, 0,  50000::numeric, 0::numeric, (CURRENT_DATE - INTERVAL '5 days'),  (CURRENT_DATE - INTERVAL '5 days'),  31, 31, 201, 'SUCCESS'
ON CONFLICT DO NOTHING;

INSERT INTO "FRM_RULE" (id, name, code, description, "ruleType", "startDate", "endDate", "jsonString", status,
                        "alertGenerationToClassificationTat", "alertActions", "ruleSeverity", "alertHierarchy_Id",
                        "alertHierarchyJson", "createdBy_Id", "updatedBy_Id", "createdAt", "updatedAt", "isDeleted", "versionNo",
                        "isScrollPending", "scrollId")
VALUES
(505, 'Credit Summation vs Account Limit (Test)', 'EWS-CRSUM-TEST',
 'Credit summation exceeds 100% of sanctioned limit over last N days', 2, CURRENT_DATE, (CURRENT_DATE + INTERVAL '5 years')::date,
 $j$
 {"name":"Credit Summation vs Account Limit (Test)","code":"EWS-CRSUM-TEST","ruleType":"EWS_BASED","alertHierarchyId":1,
  "ruleSeverity":"MEDIUM","alertGenerationToClassificationTat":7,"action":[],
  "topCondition":"AND",
  "conditions":[{"Order":1,"name":"Credit Summation vs Limit",
   "function":"creditSummationComparedToAccountLimitInLastNDays","isAdvanceField":true,
   "parameters":[{"name":"LastNDays","value":"30","type":"number"}],"relation":">","value":"100","type":"number"}]}
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
FROM "FRM_RULE" r WHERE r.id = 505
ON CONFLICT DO NOTHING;

COMMIT;
