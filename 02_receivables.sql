BEGIN;

INSERT INTO "SECURITY_DETAILS" (id, "accountId", "securityType", "securityClass", "createdAt")
VALUES (31, 31, 'STOCK', 'STK', now())
ON CONFLICT DO NOTHING;

-- createdAt staggered to match recordDate order - SignificantMovementInReceivablesInLastNTimes()
-- picks "latest" by createdAt (OrderByDescending), not recordDate. A single now() for all 3 rows
-- made that pick a tie (nondeterministic), which is why this rule intermittently failed to match.
INSERT INTO "STOCK" (id, "accountId", "stockValue", debtors, "recordDate", "createdAt")
SELECT 31, 31, 100000::numeric, 100000::numeric, (CURRENT_DATE - INTERVAL '60 days')::date, now() - INTERVAL '60 days' UNION ALL
SELECT 32, 31, 100000::numeric, 100000::numeric, (CURRENT_DATE - INTERVAL '30 days')::date, now() - INTERVAL '30 days' UNION ALL
SELECT 33, 31,  40000::numeric, 180000::numeric, CURRENT_DATE,                              now()
ON CONFLICT DO NOTHING;

INSERT INTO "FRM_RULE" (id, name, code, description, "ruleType", "startDate", "endDate", "jsonString", status,
                        "alertGenerationToClassificationTat", "alertActions", "ruleSeverity", "alertHierarchy_Id",
                        "alertHierarchyJson", "createdBy_Id", "updatedBy_Id", "createdAt", "updatedAt", "isDeleted", "versionNo",
                        "isScrollPending", "scrollId")
VALUES
(502, 'Significant Movement In Receivables (Test)', 'EWS-REC-TEST',
 'Debtors increased >30% vs average over last N months', 2, CURRENT_DATE, (CURRENT_DATE + INTERVAL '5 years')::date,
 $j$
 {"name":"Significant Movement In Receivables (Test)","code":"EWS-REC-TEST","ruleType":"EWS_BASED","alertHierarchyId":1,
  "ruleSeverity":"MEDIUM","alertGenerationToClassificationTat":7,"action":[],
  "topCondition":"AND",
  "conditions":[{"Order":1,"name":"Significant Movement In Receivables",
   "function":"significantMovementInReceivablesInLastNMonths","isAdvanceField":true,
   "parameters":[{"name":"LastNMonths","value":"3","type":"number"}],"relation":"<","value":"-30","type":"number"}]}
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
FROM "FRM_RULE" r WHERE r.id = 502
ON CONFLICT DO NOTHING;

COMMIT;
