"! ======================================================================
"! Interface: ZIF_SC_SIMULATOR
"! Description: Core interface for supply chain digital twin operations
"! ======================================================================
INTERFACE zif_sc_simulator PUBLIC.
  METHODS:
    simulate_horizon
      IMPORTING
        iv_days_forward TYPE i
      RETURNING
        VALUE(rv_health_score) TYPE p LENGTH 4 DECIMALS 2.
ENDINTERFACE.
