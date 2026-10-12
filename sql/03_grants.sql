GRANT USE CATALOG ON CATALOG capstone_gov TO `d307a8ee-2a79-4ddd-930f-3c09ac320714`;

GRANT USE CATALOG ON CATALOG capstone_gov TO `account users`;


GRANT USE SCHEMA, SELECT ON SCHEMA capstone_gov.bronze TO `d307a8ee-2a79-4ddd-930f-3c09ac320714`;
GRANT USE SCHEMA, SELECT, MODIFY, CREATE TABLE ON SCHEMA capstone_gov.silver TO `d307a8ee-2a79-4ddd-930f-3c09ac320714`;
GRANT USE SCHEMA, SELECT, MODIFY, CREATE TABLE ON SCHEMA capstone_gov.gold TO `d307a8ee-2a79-4ddd-930f-3c09ac320714`;
GRANT READ VOLUME ON VOLUME capstone_gov.bronze.raw_landing TO `d307a8ee-2a79-4ddd-930f-3c09ac320714`;



GRANT USE SCHEMA, SELECT ON SCHEMA capstone_gov.gold TO `account users`;

GRANT SELECT ON SCHEMA capstone_gov.silver TO `account users`;


REVOKE SELECT ON SCHEMA capstone_gov.silver FROM `account users`;
