using BenchmarkTools
using CpuId
using LinearAlgebra
BLAS.set_num_threads(1)

function dMMM_naive!(C, A, B)
    @assert size(C) == size(A) == size(B)
    @assert size(C, 1) == size(C, 2)
    n = size(C, 1)
    fill!(C, zero(eltype(C)))

    # - c: for columns of B and C
    # - r: for rows    of A and C
    # - k: for columns of A and rows of B
    for c in 1:n
        for r in 1:n
            c_reg = 0.0
            for k in 1:n
                @inbounds c_reg += A[r, k] * B[k, c]
            end
            @inbounds C[r, c] = c_reg
        end
    end
    return C
end

function dMMM_contiguous!(C, A, B)
    @assert size(C) == size(A) == size(B)
    @assert size(C, 1) == size(C, 2)
    n = size(C, 1)
    fill!(C, zero(eltype(C)))

    # - c: for columns of B and C
    # - r: for rows    of A and C
    # - k: for columns of A and rows of B
    for c in 1:n
        for k in 1:n
            @inbounds b = B[k, c]
            for r in 1:n
                @inbounds C[r, c] += A[r, k] * b
            end
        end
    end
    return C
end

function dMMM_cache_blocking!(C, A, B; col_blksize=16, row_blksize=128, k_blksize=16)
    @assert size(C) == size(A) == size(B)
    @assert size(C, 1) == size(C, 2)
    n = size(C, 1)
    fill!(C, zero(eltype(C)))

    # - c: for columns of B and C
    # - r: for rows    of A and C
    # - k: for columns of A and rows of B
    for ic in 1:col_blksize:n
        for ir in 1:row_blksize:n
            for ik in 1:k_blksize:n
                #
                # begin: cache blocking
                #
                for jc in ic:min(ic + col_blksize - 1, n)
                    for jk in ik:min(ik + k_blksize - 1, n)
                        @inbounds b = B[jk, jc]
                        for jr in ir:min(ir + row_blksize - 1, n)
                            @inbounds C[jr, jc] += A[jr, jk] * b
                        end
                    end
                end
                #
                # end: cache blocking
                #
            end
        end
    end
    return C
end


function main()
    N = 2048
    C = zeros(N, N)
    A = rand(N, N)
    B = rand(N, N)
    t_naive = @belapsed dMMM_naive!($C, $A, $B) samples = 3 evals = 2
    println("dMMM_naive: ", t_naive, " sec, performance = ", round(2.0e-9 * N^3 / t_naive, digits=2), " GFLOPS\n")
    t_contiguous = @belapsed dMMM_contiguous!($C, $A, $B) samples = 3 evals = 2
    println("dMMM_contiguous: ", t_contiguous, " sec, performance = ", round(2.0e-9 * N^3 / t_contiguous, digits=2), " GFLOPS\n")
    flush(stdout)
    t_cache_blocking = @belapsed dMMM_cache_blocking!($C, $A, $B) samples = 3 evals = 2
    println("dMMM_cache_blocking: ", t_cache_blocking, " sec, performance = ", round(2.0e-9 * N^3 / t_cache_blocking, digits=2), " GFLOPS\n")
    flush(stdout)
    t_BLAS = @belapsed mul!($C, $A, $B) samples = 3 evals = 2
    println("mul! (BLAS): ", t_BLAS, " sec, performance = ", round(2.0e-9 * N^3 / t_BLAS, digits=2), " GFLOPS\n")
    flush(stdout)

    println("\n\n\t Varying block sizes:")
    L1 = cachesize()[1]
    for cbs in (4, 8, 16, 32, 64), kbs in (4, 8, 16, 32, 64), rbs in (4, 128, 256, 512)
        if rbs * kbs + rbs * cbs > L1 / 8
            # A block and C block don't fit into L1 cache together
            continue
        end
        t_cache_block = @belapsed dMMM_cache_blocking!($C, $A, $B; col_blksize=$cbs, row_blksize=$rbs, k_blksize=$kbs) samples = 3 evals = 2
        println("dMMM_cache_block ($cbs, $rbs, $kbs): ", t_cache_block, " sec, performance = ", round(2.0e-9 * N^3 / t_cache_block, digits=2), " GFLOPS\n")
        flush(stdout)
    end
    return nothing
end

@time main()
