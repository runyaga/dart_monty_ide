# HHG v1 end-to-end demo: duck_query → df_filter → svg_bar_chart → svg_render
#
# Three Holy Hand Grenades packages composed in ~30 lines of Python.
# Works identically on FFI (native) and WASM (flutter run -d chrome):
#  - duck_query pulls and aggregates inline data via DuckDB SQL
#  - df_filter / df_select narrow the frame
#  - svg_bar_chart generates a chart string; svg_render hands it to the host
#
# Run in the IDE: paste or load this file, press Run.
# The host renderer writes the SVG to a temp file on native and prints the
# path, so you can open it in any SVG viewer.

requires(["duck_query", "df_filter", "df_select", "svg_bar_chart", "svg_render"])

# --- 1. Pull & aggregate with DuckDB SQL ---
# Inline VALUES so the demo needs no external CSV file and works on WASM.
data = duck_query("""
SELECT
    region,
    product,
    SUM(sales) AS total_sales
FROM (VALUES
    ('West',  'Widgets',  1200),
    ('West',  'Gadgets',   850),
    ('West',  'Gizmos',    430),
    ('East',  'Widgets',  2100),
    ('East',  'Gadgets',   970),
    ('East',  'Gizmos',    310),
    ('North', 'Widgets',   780),
    ('North', 'Gadgets',   540),
    ('North', 'Gizmos',    200),
    ('South', 'Widgets',   990),
    ('South', 'Gadgets',   660),
    ('South', 'Gizmos',    150)
) AS t(region, product, sales)
GROUP BY region, product
ORDER BY region, total_sales DESC
""")

print("Regions x products: " + str(len(data["region"])) + " rows")

# --- 2. Narrow with dataframe verbs: keep only Widgets ---
widgets = df_filter(data, where={"product": "Widgets"})
chart_data = df_select(widgets, columns=["region", "total_sales"])
print("Widgets rows: " + str(len(chart_data["region"])))

# --- 3. Render as a bar chart ---
chart_svg = svg_bar_chart(
    chart_data["region"],
    chart_data["total_sales"],
    width=500,
    height=320,
    color="#4a90d9",
    title="Widgets Sales by Region",
)

svg_render(chart_svg)
print("Chart rendered — check the console for the SVG file path.")
