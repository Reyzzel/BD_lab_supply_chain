SET search_path TO scm, public;


-- FK (PostgreSQL не індексує їх автоматично)
CREATE INDEX ix_employee_department   ON employee (department_id);
CREATE INDEX ix_order_customer        ON customer_order (customer_id);
CREATE INDEX ix_order_employee        ON customer_order (employee_id);
CREATE INDEX ix_contract_supplier     ON contract (supplier_edrpou);
CREATE INDEX ix_contract_item_product ON contract_item (product_sku);
CREATE INDEX ix_supply_warehouse      ON supply (warehouse_id);
CREATE INDEX ix_stock_product         ON warehouse_stock (product_sku);
CREATE INDEX ix_shipment_warehouse    ON shipment (warehouse_id);

-- Складені
CREATE INDEX ix_order_status_date        ON customer_order (status, order_date DESC);
CREATE INDEX ix_supply_contract_product  ON supply (contract_number, product_sku);
CREATE INDEX ix_supply_delivery_date     ON supply (delivery_date);
CREATE INDEX ix_audit_record             ON audit_log (table_name, record_id);

-- Покриваючий: підсумки продажів без звернення до таблиці
CREATE INDEX ix_order_item_product ON order_item (product_sku) INCLUDE (quantity, unit_price);

-- Лише активні записи
CREATE INDEX ix_employee_mentor       ON employee (mentor_id) WHERE mentor_id IS NOT NULL;
CREATE INDEX ix_product_active_name   ON product (name)       WHERE deleted_at IS NULL;

-- Email унікальний без урахування регістру серед невидалених клієнтів
CREATE UNIQUE INDEX uq_customer_email_active
    ON customer (lower(email)) WHERE deleted_at IS NULL AND email IS NOT NULL;

CREATE INDEX ix_supplier_name_lower ON supplier (lower(company_name));

-- Hash: пошук за точним номером телефону
CREATE INDEX ix_customer_phone_hash ON customer USING hash (phone);

-- GIN: пошук у JSONB (@>)
CREATE INDEX ix_audit_new_data_gin ON audit_log USING gin (new_data jsonb_path_ops);

-- BRIN: журнал лише доповнюється, тож changed_at зростає разом з фізичним порядком
CREATE INDEX ix_audit_changed_at_brin ON audit_log USING brin (changed_at);
