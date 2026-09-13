"! ======================================================================
"! Class: ZCL_SC_DIGITAL_TWIN
"! Title: Autonomous SAP Supply Chain Digital Twin
"! Description: Simulates multi-echelon procurement, inventory buffers,
"!              supplier disruptions, and computes optimal mitigation actions.
"! ======================================================================
CLASS zcl_sc_digital_twin DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_sc_simulator.

    TYPES:
      BEGIN OF ty_plant_node,
        plant_id       TYPE string,
        plant_name     TYPE string,
        current_stock  TYPE p LENGTH 8 DECIMALS 2,
        safety_stock   TYPE p LENGTH 8 DECIMALS 2,
        daily_demand   TYPE p LENGTH 8 DECIMALS 2,
        max_capacity   TYPE p LENGTH 8 DECIMALS 2,
      END OF ty_plant_node,
      tt_plant_node TYPE STANDARD TABLE OF ty_plant_node WITH KEY plant_id,

      BEGIN OF ty_supplier_edge,
        supplier_id    TYPE string,
        target_plant   TYPE string,
        lead_time_days TYPE i,
        reliability    TYPE p LENGTH 4 DECIMALS 2, " 0.00 to 1.00
        unit_cost      TYPE p LENGTH 8 DECIMALS 2,
        is_disrupted   TYPE abap_bool,
      END OF ty_supplier_edge,
      tt_supplier_edge TYPE STANDARD TABLE OF ty_supplier_edge WITH KEY supplier_id target_plant,

      BEGIN OF ty_action_recommendation,
        action_type    TYPE string, " e.g. STO_CREATE, PR_CREATE, EXPEDITE
        source_id      TYPE string,
        target_id      TYPE string,
        quantity       TYPE p LENGTH 8 DECIMALS 2,
        risk_score     TYPE p LENGTH 4 DECIMALS 2,
        rationale      TYPE string,
      END OF ty_action_recommendation,
      tt_action_recommendation TYPE STANDARD TABLE OF ty_action_recommendation WITH DEFAULT KEY.

    METHODS:
      constructor,
      add_plant
        IMPORTING
          is_plant TYPE ty_plant_node,
      add_supplier
        IMPORTING
          is_supplier TYPE ty_supplier_edge,
      inject_disruption
        IMPORTING
          iv_supplier_id TYPE string
          iv_lead_time_multiplier TYPE p LENGTH 4 DECIMALS 2,
      run_mrp_simulation
        RETURNING
          VALUE(rt_recommendations) TYPE tt_action_recommendation.

  PRIVATE SECTION.
    DATA:
      mt_plants     TYPE tt_plant_node,
      mt_suppliers  TYPE tt_supplier_edge,
      mo_mrp_engine TYPE REF TO zcl_mrp_optimizer.

    METHODS:
      evaluate_stockouts
        CHANGING
          ct_recs TYPE tt_action_recommendation,
      evaluate_lateral_transfers
        CHANGING
          ct_recs TYPE tt_action_recommendation.
ENDCLASS.

CLASS zcl_sc_digital_twin IMPLEMENTATION.

  METHOD constructor.
    CREATE OBJECT mo_mrp_engine.
  ENDMETHOD.

  METHOD add_plant.
    APPEND is_plant TO mt_plants.
  ENDMETHOD.

  METHOD add_supplier.
    APPEND is_supplier TO mt_suppliers.
  ENDMETHOD.

  METHOD inject_disruption.
    LOOP AT mt_suppliers ASSIGNING FIELD-SYMBOL(<fs_sup>) WHERE supplier_id = iv_supplier_id.
      <fs_sup>-is_disrupted = abap_true.
      <fs_sup>-lead_time_days = <fs_sup>-lead_time_days * iv_lead_time_multiplier.
      <fs_sup>-reliability = <fs_sup>-reliability * '0.50'.
    ENDLOOP.
  ENDMETHOD.

  METHOD run_mrp_simulation.
    CLEAR rt_recommendations.

    " 1. Check for stockout risks across plants
    evaluate_stockouts( CHANGING ct_recs = rt_recommendations ).

    " 2. Calculate optimal lateral rebalancing (Stock Transport Orders)
    evaluate_lateral_transfers( CHANGING ct_recs = rt_recommendations ).
  ENDMETHOD.

  METHOD evaluate_stockouts.
    LOOP AT mt_plants ASSIGNING FIELD-SYMBOL(<fs_plant>).
      DATA(lv_days_cover) = <fs_plant>-current_stock / <fs_plant>-daily_demand.
      
      IF lv_days_cover < 7.
        " Severe stockout risk detected
        " Find viable backup suppliers
        LOOP AT mt_suppliers ASSIGNING FIELD-SYMBOL(<fs_sup>) 
          WHERE target_plant = <fs_plant>-plant_id AND is_disrupted = abap_false.
          
          DATA(lv_order_qty) = (<fs_plant>-safety_stock * 2) - <fs_plant>-current_stock.
          IF lv_order_qty > 0.
            DATA ls_rec TYPE ty_action_recommendation.
            ls_rec-action_type = 'PR_CREATE'.
            ls_rec-source_id   = <fs_sup>-supplier_id.
            ls_rec-target_id   = <fs_plant>-plant_id.
            ls_rec-quantity    = lv_order_qty.
            ls_rec-risk_score  = 1 - <fs_sup>-reliability.
            ls_rec-rationale   = |Stock cover { lv_days_cover } days is below safety threshold of 7 days.|.
            APPEND ls_rec TO ct_recs.
          ENDIF.
        ENDLOOP.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD evaluate_lateral_transfers.
    " Find surplus plants and deficit plants
    LOOP AT mt_plants ASSIGNING FIELD-SYMBOL(<fs_deficit>) 
      WHERE current_stock < safety_stock.
      
      LOOP AT mt_plants ASSIGNING FIELD-SYMBOL(<fs_surplus>) 
        WHERE current_stock > ( safety_stock * '1.50' )
          AND plant_id <> <fs_deficit>-plant_id.
        
        DATA(lv_transfer_qty) = <fs_surplus>-current_stock - <fs_surplus>-safety_stock.
        DATA(lv_deficit_qty)  = <fs_deficit>-safety_stock - <fs_deficit>-current_stock.
        
        DATA(lv_actual_qty) = COND #( WHEN lv_transfer_qty < lv_deficit_qty 
                                      THEN lv_transfer_qty 
                                      ELSE lv_deficit_qty ).
        
        IF lv_actual_qty > 0.
          DATA ls_rec TYPE ty_action_recommendation.
          ls_rec-action_type = 'STO_CREATE'.
          ls_rec-source_id   = <fs_surplus>-plant_id.
          ls_rec-target_id   = <fs_deficit>-plant_id.
          ls_rec-quantity    = lv_actual_qty.
          ls_rec-risk_score  = '0.10'.
          ls_rec-rationale   = |Lateral stock rebalance from surplus plant { <fs_surplus>-plant_id } to { <fs_deficit>-plant_id }.|.
          APPEND ls_rec TO ct_recs.
          
          <fs_surplus>-current_stock = <fs_surplus>-current_stock - lv_actual_qty.
          <fs_deficit>-current_stock = <fs_deficit>-current_stock + lv_actual_qty.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
