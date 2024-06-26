# Copyright (c) 2016 Changhyun Kwon, Oscar Dowson, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

# PATH uses the Float64 value 1e20 to represent +infinity.
const INFINITY = 1e20

###
### License.h
###

function c_api_License_SetString(license::String)
    return @ccall PATH_SOLVER.License_SetString(license::Ptr{Cchar})::Cint
end

###
### Output_Interface.h
###

const c_api_Output_Log = Cint(1 << 0)
const c_api_Output_Status = Cint(1 << 1)
const c_api_Output_Listing = Cint(1 << 2)

mutable struct OutputData
    io::IO
end

mutable struct OutputInterface
    output_data::Ptr{Cvoid}
    print::Ptr{Cvoid}
    flush::Ptr{Cvoid}
end

# flush argument is optional and appears unused. I could not trigger
# a test that used it.
# function _c_flush(data::Ptr{Cvoid}, mode::Cint)
#     output_data = unsafe_pointer_to_objref(data)::OutputData
#     flush(output_data.io)
#     return
# end

function _c_print(data::Ptr{Cvoid}, mode::Cint, msg::Ptr{Cchar})
    if (
        mode & c_api_Output_Log == c_api_Output_Log ||
        # TODO(odow): decide whether to print the Output_Status. It has a lot of
        # information...
        # mode & c_api_Output_Status == c_api_Output_Status ||
        mode & c_api_Output_Listing == c_api_Output_Listing
    )
        output_data = unsafe_pointer_to_objref(data)::OutputData
        print(output_data.io, unsafe_string(msg))
    end
    return
end

function OutputInterface(output_data)
    _C_PRINT = @cfunction(_c_print, Cvoid, (Ptr{Cvoid}, Cint, Ptr{Cchar}))
    _C_FLUSH = C_NULL  # flush argument is optional
    # To make pointer_from_objref legal, you must ensure that output_data AND
    # the Output_Interface object outlive any ccalls. We do this in solve_mcp
    # using `gc_root`.
    return OutputInterface(pointer_from_objref(output_data), _C_PRINT, _C_FLUSH)
end

function c_api_Output_SetInterface(o::OutputInterface)
    return @ccall(
        PATH_SOLVER.Output_SetInterface(o::Ref{OutputInterface})::Cvoid,
    )
end

###
### Options.h
###

mutable struct Options
    ptr::Ptr{Cvoid}
    function Options(ptr::Ptr{Cvoid})
        o = new(ptr)
        finalizer(c_api_Options_Destroy, o)
        return o
    end
end

Base.cconvert(::Type{Ptr{Cvoid}}, x::Options) = x
Base.unsafe_convert(::Type{Ptr{Cvoid}}, x::Options) = x.ptr

function c_api_Options_Create()
    return Options(@ccall PATH_SOLVER.Options_Create()::Ptr{Cvoid})
end

function c_api_Options_Destroy(o::Options)
    return @ccall PATH_SOLVER.Options_Destroy(o::Ptr{Cvoid})::Cvoid
end

function c_api_Options_Default(o::Options)
    return @ccall PATH_SOLVER.Options_Default(o::Ptr{Cvoid})::Cvoid
end

function c_api_Options_Display(o::Options)
    return @ccall PATH_SOLVER.Options_Display(o::Ptr{Cvoid})::Cvoid
end

function c_api_Options_Read(o::Options, filename::String)
    return @ccall(
        PATH_SOLVER.Options_Read(o::Ptr{Cvoid}, filename::Ptr{Cchar})::Cvoid,
    )
end

function c_api_Path_AddOptions(o::Options)
    return @ccall PATH_SOLVER.Path_AddOptions(o::Ptr{Cvoid})::Cvoid
end

###
### Presolve_Interface.h
###

const PRESOLVE_LINEAR = 0
const PRESOLVE_NONLINEAR = 1

mutable struct PresolveData
    jac_typ::Function
end

function _c_jac_typ(data_ptr::Ptr{Cvoid}, nnz::Cint, typ_ptr::Ptr{Cint})
    data = unsafe_pointer_to_objref(data_ptr)::PresolveData
    data.jac_typ(nnz, unsafe_wrap(Array{Cint}, typ_ptr, nnz))
    return
end

mutable struct Presolve_Interface
    presolve_data::Ptr{Cvoid}
    start_pre::Ptr{Cvoid}
    start_post::Ptr{Cvoid}
    finish_pre::Ptr{Cvoid}
    finish_post::Ptr{Cvoid}
    jac_typ::Ptr{Cvoid}
    con_typ::Ptr{Cvoid}

    # To make pointer_from_objref legal, you must ensure that presolve_data AND
    # the Presolve_Interface object outlive any ccalls. We do this in solve_mcp
    # using `gc_root`.
    function Presolve_Interface(presolve_data::PresolveData)
        return new(
            pointer_from_objref(presolve_data),
            C_NULL,
            C_NULL,
            C_NULL,
            C_NULL,
            @cfunction(_c_jac_typ, Cvoid, (Ptr{Cvoid}, Cint, Ptr{Cint})),
            C_NULL,
        )
    end
end

###
### MCP_Interface.h
###

mutable struct InterfaceData
    n::Cint
    nnz::Cint
    F::Function
    J::Function
    lb::Vector{Cdouble}
    ub::Vector{Cdouble}
    z::Vector{Cdouble}
    variable_names::Vector{String}
    constraint_names::Vector{String}
end

function _c_problem_size(
    id_ptr::Ptr{Cvoid},
    n_ptr::Ptr{Cint},
    nnz_ptr::Ptr{Cint},
)
    id_data = unsafe_pointer_to_objref(id_ptr)::InterfaceData
    unsafe_store!(n_ptr, id_data.n)
    unsafe_store!(nnz_ptr, id_data.nnz)
    return
end

function _c_bounds(
    id_ptr::Ptr{Cvoid},
    n::Cint,
    z_ptr::Ptr{Cdouble},
    lb_ptr::Ptr{Cdouble},
    ub_ptr::Ptr{Cdouble},
)
    id_data = unsafe_pointer_to_objref(id_ptr)::InterfaceData
    copy!(unsafe_wrap(Array{Cdouble}, z_ptr, n), id_data.z)
    copy!(unsafe_wrap(Array{Cdouble}, lb_ptr, n), id_data.lb)
    copy!(unsafe_wrap(Array{Cdouble}, ub_ptr, n), id_data.ub)
    return
end

function _c_function_evaluation(
    id_ptr::Ptr{Cvoid},
    n::Cint,
    x_ptr::Ptr{Cdouble},
    f_ptr::Ptr{Cdouble},
)
    id_data = unsafe_pointer_to_objref(id_ptr)::InterfaceData
    x = unsafe_wrap(Array{Cdouble}, x_ptr, n)
    f = unsafe_wrap(Array{Cdouble}, f_ptr, n)
    return id_data.F(n, x, f)
end

function _c_jacobian_evaluation(
    id_ptr::Ptr{Cvoid},
    n::Cint,
    x_ptr::Ptr{Cdouble},
    wantf::Cint,
    f_ptr::Ptr{Cdouble},
    nnz_ptr::Ptr{Cint},
    col_ptr::Ptr{Cint},
    len_ptr::Ptr{Cint},
    row_ptr::Ptr{Cint},
    data_ptr::Ptr{Cdouble},
)
    id_data = unsafe_pointer_to_objref(id_ptr)::InterfaceData
    x = unsafe_wrap(Array{Cdouble}, x_ptr, n)
    err = Cint(0)
    if wantf > 0
        f = unsafe_wrap(Array{Cdouble}, f_ptr, n)
        err += id_data.F(n, x, f)
    end
    nnz = unsafe_load(nnz_ptr)::Cint
    col = unsafe_wrap(Array{Cint}, col_ptr, n)
    len = unsafe_wrap(Array{Cint}, len_ptr, n)
    row = unsafe_wrap(Array{Cint}, row_ptr, nnz)
    data = unsafe_wrap(Array{Cdouble}, data_ptr, nnz)
    err += id_data.J(n, nnz, x, col, len, row, data)
    unsafe_store!(nnz_ptr, Cint(sum(len)))
    return err
end

function _c_variable_name(
    id_ptr::Ptr{Cvoid},
    i::Cint,
    buf_ptr::Ptr{UInt8},
    buf_size::Cint,
)
    id_data = unsafe_pointer_to_objref(id_ptr)::InterfaceData
    data = fill(UInt8('\0'), buf_size)
    units = codeunits(id_data.variable_names[i])
    for j in 1:min(length(units), buf_size)-1
        data[j] = units[j]
    end
    GC.@preserve data begin
        unsafe_copyto!(buf_ptr, pointer(data), buf_size)
    end
    return
end

function _c_constraint_name(
    id_ptr::Ptr{Cvoid},
    i::Cint,
    buf_ptr::Ptr{UInt8},
    buf_size::Cint,
)
    id_data = unsafe_pointer_to_objref(id_ptr)::InterfaceData
    data = fill(UInt8('\0'), buf_size)
    units = codeunits(id_data.constraint_names[i])
    for j in 1:min(length(units), buf_size)-1
        data[j] = units[j]
    end
    GC.@preserve data begin
        unsafe_copyto!(buf_ptr, pointer(data), buf_size)
    end
    return
end

"""
    MCP_Interface

A storage struct that is used to pass problem-specific functions to PATH.
"""
mutable struct MCP_Interface
    interface_data::Ptr{Cvoid}
    problem_size::Ptr{Cvoid}
    bounds::Ptr{Cvoid}
    function_evaluation::Ptr{Cvoid}
    jacobian_evaluation::Ptr{Cvoid}
    # TODO(odow): the .h files I have don't include the hessian evaluation in
    #             MCP_Interface, but Standalone_Path.c includes it. Ask M.
    #             Ferris to look at the source.
    # Answer: there is an #ifdef to turn it on or off. In the GAMS builds it
    #         appears to be on, but we should be careful when updating PATH
    #         versions.
    hessian_evaluation::Ptr{Cvoid}
    start::Ptr{Cvoid}
    finish::Ptr{Cvoid}
    variable_name::Ptr{Cvoid}
    constraint_name::Ptr{Cvoid}
    basis::Ptr{Cvoid}

    function MCP_Interface(interface_data::InterfaceData)
        _C_PROBLEM_SIZE = @cfunction(
            _c_problem_size,
            Cvoid,
            (Ptr{Cvoid}, Ptr{Cint}, Ptr{Cint})
        )
        _C_BOUNDS = @cfunction(
            _c_bounds,
            Cvoid,
            (Ptr{Cvoid}, Cint, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble})
        )
        _C_FUNCTION_EVALUATION = @cfunction(
            _c_function_evaluation,
            Cint,
            (Ptr{Cvoid}, Cint, Ptr{Cdouble}, Ptr{Cdouble})
        )
        _C_JACOBIAN_EVALUATION = @cfunction(
            _c_jacobian_evaluation,
            Cint,
            (
                Ptr{Cvoid},
                Cint,
                Ptr{Cdouble},
                Cint,
                Ptr{Cdouble},
                Ptr{Cint},
                Ptr{Cint},
                Ptr{Cint},
                Ptr{Cint},
                Ptr{Cdouble},
            )
        )
        if isempty(interface_data.variable_names)
            _C_VARIABLE_NAME = C_NULL
        else
            _C_VARIABLE_NAME = @cfunction(
                _c_variable_name,
                Cvoid,
                (Ptr{Cvoid}, Cint, Ptr{Cuchar}, Cint)
            )
        end
        if isempty(interface_data.constraint_names)
            _C_CONSTRAINT_NAME = C_NULL
        else
            _C_CONSTRAINT_NAME = @cfunction(
                _c_constraint_name,
                Cvoid,
                (Ptr{Cvoid}, Cint, Ptr{Cuchar}, Cint)
            )
        end
        # To make pointer_from_objref legal, you must ensure that interface_data
        # AND the MCP_Interface object outlive any ccalls. We do this in
        # solve_mcp using `gc_root`.
        return new(
            pointer_from_objref(interface_data),
            _C_PROBLEM_SIZE,
            _C_BOUNDS,
            _C_FUNCTION_EVALUATION,
            _C_JACOBIAN_EVALUATION,
            C_NULL,
            C_NULL,  # See TODO note in definition of fields above.
            C_NULL,
            _C_VARIABLE_NAME,
            _C_CONSTRAINT_NAME,
            C_NULL,
        )
    end
end

mutable struct MCP
    n::Int
    ptr::Ptr{Cvoid}

    function MCP(n::Int, ptr::Ptr{Cvoid})
        m = new(n, ptr)
        finalizer(c_api_MCP_Destroy, m)
        return m
    end
end

Base.cconvert(::Type{Ptr{Cvoid}}, x::MCP) = x
Base.unsafe_convert(::Type{Ptr{Cvoid}}, x::MCP) = x.ptr

function c_api_MCP_Create(n::Int, nnz::Int)
    ptr = @ccall PATH_SOLVER.MCP_Create(n::Cint, nnz::Cint)::Ptr{Cvoid}
    return MCP(n, ptr)
end

function c_api_MCP_Jacobian_Structure_Constant(m::MCP, flag::Bool)
    @ccall PATH_SOLVER.MCP_Jacobian_Structure_Constant(
        m::Ptr{Cvoid},
        flag::Cint,
    )::Cvoid
    return
end

function c_api_MCP_Jacobian_Data_Contiguous(m::MCP, flag::Bool)
    @ccall PATH_SOLVER.MCP_Jacobian_Data_Contiguous(
        m::Ptr{Cvoid},
        flag::Cint,
    )::Cvoid
    return
end

function c_api_MCP_Destroy(m::MCP)
    if m.ptr === C_NULL
        return
    end
    @ccall PATH_SOLVER.MCP_Destroy(m::Ptr{Cvoid})::Cvoid
    return
end

function c_api_MCP_SetInterface(m::MCP, interface::MCP_Interface)
    @ccall PATH_SOLVER.MCP_SetInterface(
        m::Ptr{Cvoid},
        interface::Ref{MCP_Interface},
    )::Cvoid
    return
end

function c_api_MCP_SetPresolveInterface(m::MCP, interface::Presolve_Interface)
    @ccall PATH_SOLVER.MCP_SetPresolveInterface(
        m::Ptr{Cvoid},
        interface::Ref{Presolve_Interface},
    )::Cvoid
    return
end

function c_api_MCP_GetX(m::MCP)
    ptr = @ccall PATH_SOLVER.MCP_GetX(m::Ptr{Cvoid})::Ptr{Cdouble}
    return copy(unsafe_wrap(Array{Cdouble}, ptr, m.n))
end

###
### Types.h
###

@enum(
    MCP_Termination,
    MCP_Solved = 1,
    MCP_NoProgress,
    MCP_MajorIterationLimit,
    MCP_MinorIterationLimit,
    MCP_TimeLimit,
    MCP_UserInterrupt,
    MCP_BoundError,
    MCP_DomainError,
    MCP_Infeasible,
    MCP_Error,
    MCP_LicenseError,
    MCP_OK
)

mutable struct Information
    # Double residual;           /* Value of residual at final point             */
    residual::Cdouble
    # Double distance;           /* Distance between initial and final point     */
    distance::Cdouble
    # Double steplength;         /* Steplength taken                             */
    steplength::Cdouble
    # Double total_time;         /* Amount of time spent in the code             */
    total_time::Cdouble
    # Double basis_time;         /* Amount of time spent factoring               */
    basis_time::Cdouble

    # Double maximum_distance;   /* Maximum distance from init point allowed     */
    maximum_distance::Cdouble

    # Int major_iterations;      /* Major iterations taken                       */
    major_iterations::Cint
    # Int minor_iterations;      /* Minor iterations taken                       */
    minor_iterations::Cint
    # Int crash_iterations;      /* Crash iterations taken                       */
    crash_iterations::Cint
    # Int function_evaluations;  /* Function evaluations performed               */
    function_evaluations::Cint
    # Int jacobian_evaluations;  /* Jacobian evaluations performed               */
    jacobian_evaluations::Cint
    # Int gradient_steps;        /* Gradient steps taken                         */
    gradient_steps::Cint
    # Int restarts;              /* Restarts used                                */
    restarts::Cint

    # Int generate_output;       /* Mask where output can be displayed.          */
    generate_output::Cint
    # Int generated_output;      /* Mask where output displayed.                 */
    generated_output::Cint

    # Boolean forward;           /* Move forward?                                */
    forward::Bool
    # Boolean backtrace;         /* Back track?                                  */
    backtrace::Bool
    # Boolean gradient;          /* Take gradient step?                          */
    gradient::Bool

    # Boolean use_start;         /* Use the starting point provided?             */
    use_start::Bool
    # Boolean use_basics;        /* Use the basis provided?                      */
    use_basics::Bool

    # Boolean used_start;        /* Was the starting point given used?           */
    used_start::Bool
    # Boolean used_basics;       /* Was the initial basis given used?            */
    used_basics::Bool

    function Information(;
        generate_output::Integer = 0,
        use_start::Bool = true,
        use_basics::Bool = false,
    )
        return new(
            0.0, # residual
            0.0, # distance
            0.0, # steplength
            0.0, # total_time
            0.0, # basis_time
            0.0, # maximum_distance
            0, # major_iterations
            0, # minor_iterations
            0, # crash_iterations
            0, # function_evaluations
            0, # jacobian_evaluations
            0, # gradient_steps
            0, # restarts
            generate_output, # generate_output
            0, # generated_output
            false, # forward
            false, # backtrace
            false, # gradient
            use_start, # use_start
            use_basics, # use_basics
            false, # used_start
            false, # used_basics
        )
    end
end

###
### Path.h
###

"""
    c_api_Path_CheckLicense(n::Int, nnz::Int)

Check that the current license (stored in the environment variable
`PATH_LICENSE_STRING` if present) is valid for problems with `n` variables and
`nnz` non-zeros in the Jacobian.

Returns a nonzero value on successful completion, and a zero value on failure.
"""
function c_api_Path_CheckLicense(n::Int, nnz::Int)
    return @ccall PATH_SOLVER.Path_CheckLicense(n::Cint, nnz::Cint)::Cint
end

"""
    c_api_Path_Version()

Return a string of the PATH version.
"""
function c_api_Path_Version()
    return unsafe_string(@ccall PATH_SOLVER.Path_Version()::Ptr{Cchar})
end

"""
    c_api_Path_Solve(m::MCP, info::Information)

Returns a MCP_Termination status.
"""
function c_api_Path_Solve(m::MCP, info::Information)
    return @ccall(
        PATH_SOLVER.Path_Solve(m::Ptr{Cvoid}, info::Ref{Information})::Cint,
    )
end

###
### Standalone interface
###

"""
    solve_mcp(
        F::Function,
        J::Function
        lb::Vector{Cdouble},
        ub::Vector{Cdouble},
        z::Vector{Cdouble};
        nnz::Int = length(lb)^2,
        variable_name::Vector{String}=String[],
        constraint_name::Vector{String}=String[],
        silent::Bool = false,
        generate_output::Integer = 0,
        use_start::Bool = true,
        use_basics::Bool = false,
        jacobian_structure_constant::Bool = false,
        jacobian_data_contiguous::Bool = false,
        jacobian_linear_elements::Vector{Int} = Int[],
        kwargs...
    )

Mathematically, the mixed complementarity problem is to find an x such that
for each i, at least one of the following hold:

   1.  F_i(x) = 0, lb_i <= (x)_i <= ub_i
   2.  F_i(x) > 0, (x)_i = lb_i
   3.  F_i(x) < 0, (x)_i = ub_i

where F is a given function from R^n to R^n, and lb and ub are prescribed
lower and upper bounds.

## The `F` argument

`F` is a function that calculates the value of function ``F(x)`` and stores the
result in `f`. It must have the signature:
```julia
function F(n::Cint, x::Vector{Cdouble}, f::Vector{Cdouble})
    for i in 1:n
        f[i] = ... do stuff ...
    end
    return Cint(0)
end
```

## The `J` argument

`J` is a function that calculates the Jacobiann of the function ``F(x)``. The
Jacobian is a square sparse matrix. It must have the signature:
```julia
function J(
    n::Cint,
    nnz::Cint,
    x::Vector{Cdouble},
    col::Vector{Cint},
    len::Vector{Cint},
    row::Vector{Cint},
    data::Vector{Cdouble},
)
    # ...
    return Cint(0)
end
```
where:

 * `n` is the number of variables (which is also the number rows and columns in
   the Jacobian matrix).
 * `nnz` is the maximum number of non-zero terms in the Jacobian. This value is
   chosen by the user as the `nnz` argumennt to `solve_mcp`.
 * `x` is the value of the decision variables at which to evaluate the Jacobian.

The remaining arguments, `col`, `len`, `row`, and `data`, specify a sparse
column representation of the Jacobian matrix. These must be filled in by your
function.

 * `col` is a length `n` vector, where `col[i]` is the 1-indexed position of the
   start of the non-zeros in column `i` in the `data` vector.
 * `len` is a length `n` vector, where `len[i]` is the number of non-zeros in
   column `i`.

Together, `col` and `len` can be used to form a range of indices in `row` and
`data` corresponding to the non-zero elements of column `i` in the Jacobian.
Thus, we can iterate over the non-zeros in the Jacobian using:
```julia
for i in 1:n
    for k in (col[i]):(col[i] + len[i] - 1)
        row[k] = ... the 1-indexed row of the k'th non-zero in the Jacobian
        data[k] = ... the value of the k'th non-zero in the Jacobian
    end
end
```

To improve performance, see the `jacobian_structure_constant` and
`jacobian_data_contiguous` keyword arguments.

## Other positional arguments

 * `lb`: a vector of the variable lower bounds
 * `ub`: a vector of the variable upper bounds
 * `z`: an initial starting point for the search. You can disable this by
   passing an empty vector and settig `use_start = false`

## Keyword arguments

 * `nnz`: the maximum number of non-zeros in the Jacobian matrix. If not
   specified if defaults to the dense estimate of `n^2` where `n` is the number
   of variables.
 * `variable_name`: a vector of variable names. This can improve the legibility
   of the output printed by PATH, particularly if there are issues associated
   with a particular variable.
 * `constraint_name`: a vector of constraint names. This can improve the
   legibility of the output printed by PATH, particularly if there are issues
   associated with a particular row of the `F` function.
 * `silent`: set `silent = true` to disable printing.
 * `generate_output`: an integer mask passed to the C API of PATH to dictate
   with output can be displayed.
 * `use_start`: set `use_start = false` to disable the use of the startint point
   `z`.
 * `use_basics`: set `use_basics = true` to use the basis provided.
 * `jacobian_structure_constant`: if `true`, the sparsity pattern of the
   Jacobian matrix must be constant between evaluations. You can improve
   performance by setting this to `true` and filling the `col`, `len` and `row`
   on the first evaluation only.
 * `jacobian_data_contiguous`: if `true`, the Jacobian data is stored
   contiguously from `1..nnz` in the `row` and `data` arrays of the Jacobian
   callback. In most cases, you can improve performance by settinng this to
   `true`. It is `false` by default for the general case.
 * `jacobian_linear_elements`: a vector of the 1-indexed indices of the Jacobian
   `data` array that appear linearly in the Jacobian, that is, their value is
   independent of the point `x` at which the Jacobian is evaluated. If you set
   this option, you must also set `jacobian_structure_constant = true`.
 * `kwargs`: other options passed to directly to PATH.
"""
function solve_mcp(
    F::Function,
    J::Function,
    lb::Vector{Cdouble},
    ub::Vector{Cdouble},
    z::Vector{Cdouble};
    nnz::Int = length(lb)^2,
    variable_names::Vector{String} = String[],
    constraint_names::Vector{String} = String[],
    silent::Bool = false,
    generate_output::Integer = 0,
    use_start::Bool = true,
    use_basics::Bool = false,
    jacobian_structure_constant::Bool = false,
    jacobian_data_contiguous::Bool = false,
    jacobian_linear_elements::Vector{Int} = Int[],
    kwargs...,
)
    @assert length(z) == length(lb) == length(ub)
    n = length(z)
    if nnz > typemax(Cint)
        return MCP_Error, nothing, nothing
    elseif n == 0
        return MCP_Solved, nothing, nothing
    end
    # gc_root is used to store various objects to prevent them from being GC'd.
    gc_root = IdDict()
    GC.@preserve gc_root begin
        out_io = silent ? IOBuffer() : stdout
        output_data = OutputData(out_io)
        # We shouldn't GC output_data until we exit the GC.@preserve block.
        gc_root[output_data] = true
        output_interface = OutputInterface(output_data)
        # We shouldn't GC output_interface until we exit the GC.@preserve block.
        gc_root[output_interface] = true
        c_api_Output_SetInterface(output_interface)
        # We need to call `c_api_Path_CheckLicense` _after_ setting the output
        # interface because CheckLicense may try to print to the screen.
        if c_api_Path_CheckLicense(n, nnz) == 0
            return MCP_LicenseError, nothing, nothing
        end
        o = c_api_Options_Create()
        # Options has a finalizer. We don't want that to run until we exit the
        # GC.@preserve block.
        gc_root[o] = true
        c_api_Path_AddOptions(o)
        c_api_Options_Default(o)
        m = c_api_MCP_Create(n, nnz)
        if jacobian_structure_constant
            c_api_MCP_Jacobian_Structure_Constant(m, true)
        end
        if jacobian_data_contiguous
            c_api_MCP_Jacobian_Data_Contiguous(m, true)
        end
        id_data = InterfaceData(
            Cint(n),
            Cint(nnz),
            F,
            J,
            lb,
            ub,
            z,
            variable_names,
            constraint_names,
        )
        # We shouldn't GC id_data until we exit the GC.@preserve block.
        gc_root[id_data] = true
        m_interface = MCP_Interface(id_data)
        # We shouldn't GC m_interface until we exit the GC.@preserve block.
        gc_root[m_interface] = true
        c_api_MCP_SetInterface(m, m_interface)
        if jacobian_structure_constant && !isempty(jacobian_linear_elements)
            function presolve_fn(::Cint, types::Vector{Cint})
                types[jacobian_linear_elements] .= PRESOLVE_LINEAR
                return
            end
            presolve_data = PresolveData(presolve_fn)
            # We shouldn't GC presolve_data until we exit the GC.@preserve block.
            gc_root[presolve_data] = true
            presolve_interface = Presolve_Interface(presolve_data)
            # We shouldn't GC presolve_interface until we exit the GC.@preserve
            # block.
            gc_root[presolve_interface] = true
            c_api_MCP_SetPresolveInterface(m, presolve_interface)
        end
        if length(kwargs) > 0
            mktemp() do path, io
                println(
                    io,
                    "* Automatically generated by PATH.jl. Do not edit.",
                )
                for (key, val) in kwargs
                    println(io, key, " ", val)
                end
                close(io)
                return c_api_Options_Read(o, path)
            end
        end
        c_api_Options_Display(o)
        info = Information(;
            generate_output = generate_output,
            use_start = use_start,
            use_basics = use_basics,
        )
        status = c_api_Path_Solve(m, info)
        X = c_api_MCP_GetX(m)
    end  # GC.@preserve
    # TODO(odow): I don't know why, but manually calling MCP_Destroy was
    # necessary to avoid a segfault on Julia 1.0 when using LUSOL. I guess it's
    # something to do with the timing of when things need to get freed on the
    # PATH side? i.e., MCP_Destroy before other things?
    c_api_MCP_Destroy(m)
    m.ptr = C_NULL
    return MCP_Termination(status), X, info
end

function _linear_function(M::AbstractMatrix, q::Vector)
    if size(M, 1) != size(M, 2)
        error("M not square! size = $(size(M))")
    elseif size(M, 1) != length(q)
        error("q is wrong shape. Expected $(size(M, 1)), got $(length(q)).")
    end
    return function F(n::Cint, x::Vector{Cdouble}, f::Vector{Cdouble})
        f .= M * x .+ q
        return Cint(0)
    end
end

function _linear_jacobian(M::SparseArrays.SparseMatrixCSC{Cdouble,Cint})
    # Size is checked with error message in _linear_function.
    @assert size(M, 1) == size(M, 2)
    return function J(
        n::Cint,
        nnz::Cint,
        x::Vector{Cdouble},
        col::Vector{Cint},
        len::Vector{Cint},
        row::Vector{Cint},
        data::Vector{Cdouble},
    )
        @assert n == length(x) == length(col) == length(len) == size(M, 1)
        @assert nnz == length(row) == length(data)
        @assert nnz >= SparseArrays.nnz(M)
        for i in 1:n
            col[i] = M.colptr[i]
            len[i] = M.colptr[i+1] - M.colptr[i]
        end
        for (i, v) in enumerate(SparseArrays.rowvals(M))
            row[i] = v
        end
        for (i, v) in enumerate(SparseArrays.nonzeros(M))
            data[i] = v
        end
        return Cint(0)
    end
end

"""
    solve_mcp(;
        M::SparseArrays.SparseMatrixCSC{Cdouble, Cint},
        q::Vector{Cdouble},
        lb::Vector{Cdouble},
        ub::Vector{Cdouble},
        z::Vector{Cdouble};
        kwargs...
    )

Mathematically, the mixed complementarity problem is to find an x such that
for each i, at least one of the following hold:

   1.  F_i(x) = 0, lb_i <= (x)_i <= ub_i
   2.  F_i(x) > 0, (x)_i = lb_i
   3.  F_i(x) < 0, (x)_i = ub_i

where F is a function `F(x) = M * x + q` from R^n to R^n, and lb and ub are
prescribed lower and upper bounds.

`z` is an initial starting point for the search.
"""
function solve_mcp(
    M::SparseArrays.SparseMatrixCSC{Cdouble,Cint},
    q::Vector{Cdouble},
    lb::Vector{Cdouble},
    ub::Vector{Cdouble},
    z::Vector{Cdouble};
    nnz = SparseArrays.nnz(M),
    kwargs...,
)
    return solve_mcp(
        _linear_function(M, q),
        _linear_jacobian(M),
        lb,
        ub,
        z;
        nnz = nnz,
        jacobian_structure_constant = true,
        jacobian_data_contiguous = true,
        jacobian_linear_elements = collect(1:nnz),
        kwargs...,
    )
end
