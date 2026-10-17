SET search_path TO scm, public;

-- Роль застосунку: читання лише з VIEW, запис лише через процедури
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'scm_app') THEN
        CREATE ROLE scm_app NOLOGIN;
    END IF;
END;
$$;

REVOKE ALL ON ALL TABLES IN SCHEMA scm FROM PUBLIC, scm_app;
GRANT USAGE ON SCHEMA scm TO scm_app;

GRANT SELECT ON
    v_app_user, v_department, v_employee, v_customer, v_product, v_supplier, v_contract,
    v_warehouse, v_order_summary, v_order_item, v_supply_detail, v_shipment, v_stock,
    v_audit_trail, v_deleted_records
TO scm_app;

GRANT EXECUTE ON ALL FUNCTIONS  IN SCHEMA scm TO scm_app;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA scm TO scm_app;

-- Логін для застосунку (виконати один раз, пароль змініть):
-- CREATE ROLE scm_api LOGIN PASSWORD 'change_me' IN ROLE scm_app;
-- ALTER ROLE scm_api SET search_path = scm, public;
