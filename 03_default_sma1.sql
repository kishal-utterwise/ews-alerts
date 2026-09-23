BEGIN;

-- No SMA_LOG insert here - the shared snapshot (account 31, id 201) that both this rule and
-- Quick SMA read is seeded once in 00_foundation.sql, so the same account satisfies both.

INSERT INTO "FRM_RULE" (id, name, code, description, "ruleType", "startDate", "endDate", "jsonString", status,
                        "alertGenerationToClassificationTat", "alertActions", "ruleSeverity", "alertHierarchy_Id",
                        "alertHierarchyJson", "createdBy_Id", "updatedBy_Id", "createdAt", "updatedAt", "isDeleted", "versionNo",
                        "isScrollPending", "scrollId")
VALUES
(503, 'Default In SMA1 (Test)', 'EWS-SMA1-TEST',
 'Account overdue 31-60 days as of evaluation date, over last N months', 2, CURRENT_DATE, (CURRENT_DATE + INTERVAL '5 years')::date,
 $j$
 {"name":"Default In SMA1 (Test)","code":"EWS-SMA1-TEST","ruleType":"EWS_BASED","alertHierarchyId":1,
  "ruleSeverity":"MEDIUM","alertGenerationToClassificationTat":7,"action":[],
  "topCondition":"AND",
  "conditions":[{"Order":1,"name":"Default In SMA1",
   "function":"defaultInSMA1InLastNMonths","isAdvanceField":true,
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
FROM "FRM_RULE" r WHERE r.id = 503
ON CONFLICT DO NOTHING;

COMMIT;
