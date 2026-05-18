# Shared text-based plotting helpers (stdlib only — no Plots.jl dependency)

function bar_chart(labels, values; title="", width=40, unit="")
    isempty(values) && return
    max_v = maximum(abs.(values))
    println("\n  $title")
    println("  " * "═" ^ (width + 26))
    for (l, v) in zip(labels, values)
        filled = max_v > 0 ? round(Int, abs(v) / max_v * width) : 0
        bar    = "█" ^ filled * "░" ^ (width - filled)
        vstr   = lpad(round(v; digits=2), 10)
        println("  $(rpad(l, 12)) │ $bar $vstr $unit")
    end
    println("  " * "─" ^ (width + 26))
end

function line_chart(ys::AbstractVector; title="", ylabel="", height=10, width=60)
    isempty(ys) && return
    n      = length(ys)
    step   = max(1, div(n, width))
    ys_ds  = [ys[i] for i in 1:step:n]
    mn, mx = minimum(ys_ds), maximum(ys_ds)
    rng    = mx == mn ? 1.0 : mx - mn
    println("\n  $title")
    println("  " * "─" ^ (length(ys_ds) + 12))
    for row in height:-1:1
        thresh = mn + (row - 1) / height * rng
        label  = row == height ? lpad(round(mx; digits=1), 8) :
                 row == 1      ? lpad(round(mn; digits=1), 8) : " " ^ 8
        pts    = join(ys_ds[i] >= thresh ? "▄" : " " for i in eachindex(ys_ds))
        println("  $label │$pts")
    end
    println("  " * " " ^ 9 * "└" * "─" ^ length(ys_ds))
    println("  " * " " ^ 10 * rpad("1", div(length(ys_ds), 2)) * "$(length(ys)) ($ylabel)")
end

function multi_line_chart(series::Vector{<:AbstractVector}, labels;
                          title="", height=10, width=60)
    isempty(series) && return
    chars  = ['▄', '▪', '●', '◆']
    all_y  = vcat(series...)
    mn, mx = minimum(all_y), maximum(all_y)
    rng    = mx == mn ? 1.0 : mx - mn
    n      = minimum(length.(series))
    step   = max(1, div(n, width))
    println("\n  $title")
    legend = join("  $(chars[i]) $(labels[i])" for i in eachindex(labels))
    println("  Legend:$legend")
    println("  " * "─" ^ (div(n, step) + 12))
    for row in height:-1:1
        thresh = mn + (row - 1) / height * rng
        label  = row == height ? lpad(round(mx; digits=1), 8) :
                 row == 1      ? lpad(round(mn; digits=1), 8) : " " ^ 8
        line   = ""
        for col in 1:step:n
            hits = [s[col] >= thresh for s in series]
            idx  = findfirst(hits)
            line *= isnothing(idx) ? " " : string(chars[idx])
        end
        println("  $label │$line")
    end
    println("  " * " " ^ 9 * "└" * "─" ^ div(n, step))
end

function text_table(headers, rows; title="")
    println("\n  $title")
    widths = [max(length(string(h)), maximum(length(string(r[i])) for r in rows))
              for (i, h) in enumerate(headers)]
    n   = length(widths)
    top = "  ┌" * join("─"^(w+2) * (i < n ? "┬" : "┐") for (i,w) in enumerate(widths))
    sep = "  ├" * join("─"^(w+2) * (i < n ? "┼" : "┤") for (i,w) in enumerate(widths))
    bot = "  └" * join("─"^(w+2) * (i < n ? "┴" : "┘") for (i,w) in enumerate(widths))
    hdr = "  │" * join(" $(rpad(string(h), w)) │" for (h,w) in zip(headers, widths))
    println(top); println(hdr); println(sep)
    for row in rows
        println("  │" * join(" $(rpad(string(row[i]), widths[i])) │" for i in eachindex(headers)))
    end
    println(bot)
end

function heatmap_text(M::AbstractMatrix, row_labels, col_labels; title="")
    shades = [' ', '░', '▒', '▓', '█']
    mn, mx = minimum(M), maximum(M)
    rng    = mx == mn ? 1.0 : mx - mn
    col_w  = maximum(length.(string.(col_labels)))
    lbl_w  = maximum(length.(string.(row_labels)))
    println("\n  $title")
    println("  " * " " ^ (lbl_w + 3) *
            join(rpad(string(c), col_w + 2) for c in col_labels))
    for (i, rl) in enumerate(row_labels)
        cells = join(begin
            idx = round(Int, (M[i, j] - mn) / rng * (length(shades) - 1)) + 1
            c   = shades[clamp(idx, 1, length(shades))]
            lpad(string(c) ^ col_w, col_w + 2)
        end for j in eachindex(col_labels))
        println("  $(rpad(rl, lbl_w)) │$cells")
    end
    println("  Scale: $(round(mn,digits=2)) $(shades[1])░▒▓$(shades[end]) $(round(mx,digits=2))")
end
