# Three-phase specific constraints


""
function constraint_kcl_shunt_slack(pm::GenericPowerModel, i::Int; nw::Int=pm.cnw, cnd::Int=pm.ccnd)
    if !haskey(con(pm, nw, cnd), :kcl_p)
        con(pm, nw, cnd)[:kcl_p] = Dict{Int,ConstraintRef}()
    end
    if !haskey(con(pm, nw, cnd), :kcl_q)
        con(pm, nw, cnd)[:kcl_q] = Dict{Int,ConstraintRef}()
    end

    bus = ref(pm, nw, :bus, i)
    bus_arcs = ref(pm, nw, :bus_arcs, i)
    bus_arcs_dc = ref(pm, nw, :bus_arcs_dc, i)
    bus_gens = ref(pm, nw, :bus_gens, i)
    bus_loads = ref(pm, nw, :bus_loads, i)
    bus_shunts = ref(pm, nw, :bus_shunts, i)

    bus_pd = Dict(k => ref(pm, nw, :load, k, "pd", cnd) for k in bus_loads)
    bus_qd = Dict(k => ref(pm, nw, :load, k, "qd", cnd) for k in bus_loads)

    bus_gs = Dict(k => ref(pm, nw, :shunt, k, "gs", cnd) for k in bus_shunts)
    bus_bs = Dict(k => ref(pm, nw, :shunt, k, "bs", cnd) for k in bus_shunts)

    constraint_kcl_shunt_slack(pm, nw, cnd, i, bus_arcs, bus_arcs_dc, bus_gens, bus_pd, bus_qd, bus_gs, bus_bs)
end


""
function constraint_tp_voltage(pm::GenericPowerModel; nw::Int=pm.cnw, cnd::Int=pm.ccnd)
    constraint_tp_voltage(pm, nw, cnd)
end


""
function constraint_ohms_tp_yt_from(pm::GenericPowerModel, i::Int; nw::Int=pm.cnw, cnd::Int=pm.ccnd)
    branch = ref(pm, nw, :branch, i)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    g, b = PMs.calc_branch_y(branch)
    tr, ti = PMs.calc_branch_t(branch)
    g_fr = branch["g_fr"]
    b_fr = branch["b_fr"]
    tm = branch["tap"]

    constraint_ohms_tp_yt_from(pm, nw, cnd, f_bus, t_bus, f_idx, t_idx, g, b, g_fr, b_fr, tr, ti, tm)
end


""
function constraint_ohms_tp_yt_to(pm::GenericPowerModel, i::Int; nw::Int=pm.cnw, cnd::Int=pm.ccnd)
    branch = ref(pm, nw, :branch, i)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    g, b = PMs.calc_branch_y(branch)
    tr, ti = PMs.calc_branch_t(branch)
    g_to = branch["g_to"]
    b_to = branch["b_to"]
    tm = branch["tap"]

    constraint_ohms_tp_yt_to(pm, nw, cnd, f_bus, t_bus, f_idx, t_idx, g, b, g_to, b_to, tr, ti, tm)
end


""
function constraint_ohms_tp_yt_from_on_off(pm::GenericPowerModel, i::Int; nw::Int=pm.cnw, cnd::Int=pm.ccnd)
    branch = ref(pm, nw, :branch, i)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    g, b = PMs.calc_branch_y(branch)
    tr, ti = PMs.calc_branch_t(branch)
    g_fr = branch["g_fr"]
    b_fr = branch["b_fr"]
    tm = branch["tap"]

    vad_min = [ref(pm, nw, :off_angmin, c) for c in PMs.conductor_ids(pm)]
    vad_max = [ref(pm, nw, :off_angmax, c) for c in PMs.conductor_ids(pm)]

    constraint_ohms_tp_yt_from_on_off(pm, nw, cnd, i, f_bus, t_bus, f_idx, t_idx, g, b, g_fr, b_fr, tr, ti, tm, vad_min, vad_max)
end


""
function constraint_ohms_tp_yt_to_on_off(pm::GenericPowerModel, i::Int; nw::Int=pm.cnw, cnd::Int=pm.ccnd)
    branch = ref(pm, nw, :branch, i)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    g, b = PMs.calc_branch_y(branch)
    tr, ti = PMs.calc_branch_t(branch)
    g_to = branch["g_to"]
    b_to = branch["b_to"]
    tm = branch["tap"]

    vad_min = [ref(pm, nw, :off_angmin, c) for c in PMs.conductor_ids(pm)]
    vad_max = [ref(pm, nw, :off_angmax, c) for c in PMs.conductor_ids(pm)]

    constraint_ohms_tp_yt_to_on_off(pm, nw, cnd, i, f_bus, t_bus, f_idx, t_idx, g, b, g_to, b_to, tr, ti, tm, vad_min, vad_max)
end


""
function constraint_tp_theta_ref(pm::GenericPowerModel, i::Int; nw::Int=pm.cnw, cnd::Int=pm.ccnd)
    constraint_tp_theta_ref(pm, nw, cnd, i)
end


""
function constraint_tp_voltage_magnitude_difference(pm::GenericPowerModel, i::Int; nw::Int=pm.cnw, cnd::Int=pm.ccnd)
    branch = ref(pm, nw, :branch, i)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    r = branch["br_r"]
    x = branch["br_x"]
    g_sh_fr = branch["g_fr"]
    b_sh_fr = branch["b_fr"]
    tm = branch["tap"]

    constraint_tp_voltage_magnitude_difference(pm, nw, cnd, i, f_bus, t_bus, f_idx, t_idx, r, x, g_sh_fr, b_sh_fr, tm)
end