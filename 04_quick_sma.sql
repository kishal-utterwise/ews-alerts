BEGIN;

-- No SMA_LOG/ACCOUNT insert here - reuses the shared snapshot (account 31, id 201) seeded once in
-- 00_foundation.sql, same row "Default In SMA1" reads, so one account satisfies both conditions
-- (needed for the app's combined AND/OR rules, not just each condition tested standalone).
-- That row already lands inside QuickSMAInLastNMonths()'s current-month-only window and account
-- 31's dateOfOpening (foundation: 1 month ago) already satisfies the "recently opened" check.

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
