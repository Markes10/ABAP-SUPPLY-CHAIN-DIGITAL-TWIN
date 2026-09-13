"! ======================================================================
"! Class: ZCL_MRP_OPTIMIZER
"! Description: Material Requirements Planning & Safety Stock Optimization
"! ======================================================================
CLASS zcl_mrp_optimizer DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS:
      calculate_eoq
        IMPORTING
          iv_annual_demand TYPE p
          iv_order_cost    TYPE p
          iv_holding_cost  TYPE p
        RETURNING
          VALUE(rv_eoq)    TYPE p,
      calculate_dynamic_safety_stock
        IMPORTING
          iv_service_level_factor TYPE p " e.g. 1.65 for 95%
          iv_std_dev_demand       TYPE p
          iv_lead_time_days       TYPE p
        RETURNING
          VALUE(rv_safety_stock)  TYPE p.
ENDCLASS.

CLASS zcl_mrp_optimizer IMPLEMENTATION.
  METHOD calculate_eoq.
    IF iv_holding_cost > 0.
      rv_eoq = sqrt( ( 2 * iv_annual_demand * iv_order_cost ) / iv_holding_cost ).
    ELSE.
      rv_eoq = 0.
    ENDIF.
  ENDMETHOD.

  METHOD calculate_dynamic_safety_stock.
    rv_safety_stock = iv_service_level_factor * iv_std_dev_demand * sqrt( iv_lead_time_days ).
  ENDMETHOD.
ENDCLASS.
