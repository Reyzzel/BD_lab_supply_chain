SET search_path TO scm, public;

-- v_<сутність> показують лише активні записи

-- Без password_hash
CREATE VIEW v_app_user AS
SELECT u.id, u.username, u.role, u.employee_id, e.full_name AS employee_name
  FROM app_user u
  LEFT JOIN employee e ON e.id = u.employee_id AND e.deleted_at IS NULL
 WHERE u.is_active;

CREATE VIEW v_department AS
SELECT d.id, d.name, d.phone,
       d.head_employee_id, h.full_name AS head_name,
       (SELECT count(*) FROM employee e
         WHERE e.department_id = d.id AND e.deleted_at IS NULL) AS employees_count,
       d.updated_at, u.username AS updated_by_username
  FROM department d
  JOIN employee h      ON h.id = d.head_employee_id
  LEFT JOIN app_user u ON u.id = d.updated_by;

CREATE VIEW v_employee AS
SELECT e.id, e.full_name, e.position, e.salary, e.hire_date,
       e.department_id, d.name AS department_name,
       e.mentor_id, m.full_name AS mentor_name,
       (d.head_employee_id = e.id) AS is_head,
       e.updated_at, u.username AS updated_by_username
  FROM employee e
  JOIN department d     ON d.id = e.department_id
  LEFT JOIN employee m  ON m.id = e.mentor_id
  LEFT JOIN app_user u  ON u.id = e.updated_by
 WHERE e.deleted_at IS NULL;

CREATE VIEW v_customer AS
SELECT c.id, c.full_name, c.phone, c.email, c.address,
       c.created_at, c.updated_at, c.updated_by, u.username AS updated_by_username
  FROM customer c
  LEFT JOIN app_user u ON u.id = c.updated_by
 WHERE c.deleted_at IS NULL;

CREATE VIEW v_product AS
SELECT p.sku, p.name, p.price, p.category,
       el.warranty_months, cl.size, cl.material,
       COALESCE(st.total_stock, 0)::integer AS total_stock,
       p.updated_at, p.updated_by, u.username AS updated_by_username
  FROM product p
  LEFT JOIN electronics el ON el.product_sku = p.sku
  LEFT JOIN clothing    cl ON cl.product_sku = p.sku
  LEFT JOIN (SELECT ws.product_sku, sum(ws.quantity) AS total_stock
               FROM warehouse_stock ws
               JOIN warehouse w ON w.id = ws.warehouse_id AND w.deleted_at IS NULL
              GROUP BY ws.product_sku) st ON st.product_sku = p.sku
  LEFT JOIN app_user u ON u.id = p.updated_by
 WHERE p.deleted_at IS NULL;

CREATE VIEW v_supplier AS
SELECT s.edrpou, s.company_name, s.phone, s.email,
       s.updated_at, u.username AS updated_by_username
  FROM supplier s
  LEFT JOIN app_user u ON u.id = s.updated_by
 WHERE s.deleted_at IS NULL;

CREATE VIEW v_contract AS
SELECT c.contract_number, c.supplier_edrpou, s.company_name AS supplier_name,
       c.sign_date, c.expiry_date,
       (current_date BETWEEN c.sign_date AND c.expiry_date) AS is_valid_today,
       (SELECT count(*) FROM contract_item ci WHERE ci.contract_number = c.contract_number) AS items_count,
       c.updated_at, u.username AS updated_by_username
  FROM contract c
  JOIN supplier s      ON s.edrpou = c.supplier_edrpou
  LEFT JOIN app_user u ON u.id = c.updated_by
 WHERE c.deleted_at IS NULL;

CREATE VIEW v_warehouse AS
SELECT w.id, w.name, w.address,
       COALESCE((SELECT sum(ws.quantity) FROM warehouse_stock ws WHERE ws.warehouse_id = w.id), 0)::integer
           AS total_units,
       w.updated_at, u.username AS updated_by_username
  FROM warehouse w
  LEFT JOIN app_user u ON u.id = w.updated_by
 WHERE w.deleted_at IS NULL;

CREATE VIEW v_order_summary AS
SELECT o.order_number, o.order_date, o.status,
       o.customer_id, c.full_name AS customer_name,
       o.employee_id, e.full_name AS employee_name,
       COALESCE(t.items_count, 0)::integer      AS items_count,
       COALESCE(t.total_amount, 0)::numeric(12,2) AS total_amount,
       sh.id AS shipment_id, sh.status AS shipment_status, w.name AS shipment_warehouse,
       o.updated_at, o.updated_by, u.username AS updated_by_username
  FROM customer_order o
  JOIN customer c       ON c.id = o.customer_id
  JOIN employee e       ON e.id = o.employee_id
  LEFT JOIN (SELECT order_number, count(*) AS items_count, sum(quantity * unit_price) AS total_amount
               FROM order_item GROUP BY order_number) t ON t.order_number = o.order_number
  LEFT JOIN shipment sh  ON sh.order_number = o.order_number
  LEFT JOIN warehouse w  ON w.id = sh.warehouse_id
  LEFT JOIN app_user u   ON u.id = o.updated_by;

CREATE VIEW v_order_item AS
SELECT oi.order_number, oi.line_number, oi.product_sku,
       p.name AS product_name, p.category,
       oi.quantity, oi.unit_price,
       (oi.quantity * oi.unit_price)::numeric(12,2) AS line_total
  FROM order_item oi
  JOIN product p ON p.sku = oi.product_sku;

CREATE VIEW v_supply_detail AS
SELECT s.id, s.contract_number,
       c.supplier_edrpou, sup.company_name AS supplier_name,
       s.product_sku, p.name AS product_name,
       s.warehouse_id, w.name AS warehouse_name,
       s.delivery_date, s.quantity, ci.agreed_price,
       (s.quantity * ci.agreed_price)::numeric(14,2) AS amount,
       s.status, s.updated_at, u.username AS updated_by_username
  FROM supply s
  JOIN contract c       ON c.contract_number = s.contract_number
  JOIN supplier sup     ON sup.edrpou = c.supplier_edrpou
  JOIN contract_item ci ON ci.contract_number = s.contract_number AND ci.product_sku = s.product_sku
  JOIN product p        ON p.sku = s.product_sku
  JOIN warehouse w      ON w.id = s.warehouse_id
  LEFT JOIN app_user u  ON u.id = s.updated_by;

CREATE VIEW v_shipment AS
SELECT sh.id, sh.order_number, sh.warehouse_id, w.name AS warehouse_name,
       sh.shipped_at, sh.tracking_number, sh.status,
       sh.updated_at, u.username AS updated_by_username
  FROM shipment sh
  JOIN warehouse w     ON w.id = sh.warehouse_id
  LEFT JOIN app_user u ON u.id = sh.updated_by;

CREATE VIEW v_stock AS
SELECT ws.warehouse_id, w.name AS warehouse_name,
       ws.product_sku, p.name AS product_name, p.category,
       ws.quantity, ws.updated_at
  FROM warehouse_stock ws
  JOIN warehouse w ON w.id  = ws.warehouse_id AND w.deleted_at IS NULL
  JOIN product p   ON p.sku = ws.product_sku  AND p.deleted_at IS NULL;

CREATE VIEW v_audit_trail AS
SELECT a.id, a.changed_at, a.table_name, a.record_id, a.operation,
       a.changed_by, u.username, a.old_data, a.new_data
  FROM audit_log a
  LEFT JOIN app_user u ON u.id = a.changed_by;

-- Усі soft-deleted записи
CREATE VIEW v_deleted_records AS
SELECT x.table_name, x.record_id, x.title, x.deleted_at, u.username AS deleted_by
  FROM (
        SELECT 'employee'::text  AS table_name, id::text AS record_id, full_name::text AS title, deleted_at, updated_by FROM employee  WHERE deleted_at IS NOT NULL
  UNION ALL SELECT 'customer',  id::text,        full_name,        deleted_at, updated_by FROM customer  WHERE deleted_at IS NOT NULL
  UNION ALL SELECT 'product',   sku,             name,             deleted_at, updated_by FROM product   WHERE deleted_at IS NOT NULL
  UNION ALL SELECT 'supplier',  edrpou,          company_name,     deleted_at, updated_by FROM supplier  WHERE deleted_at IS NOT NULL
  UNION ALL SELECT 'contract',  contract_number, contract_number,  deleted_at, updated_by FROM contract  WHERE deleted_at IS NOT NULL
  UNION ALL SELECT 'warehouse', id::text,        name,             deleted_at, updated_by FROM warehouse WHERE deleted_at IS NOT NULL
       ) x
  LEFT JOIN app_user u ON u.id = x.updated_by;
