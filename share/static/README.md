# Static report assets

`report.css` is the operator-editable stylesheet for the static HTML statistics
page. The installer copies it to the configuration directory and updates
`html_report.stylesheet_file`. `postfilterctl report-generate` embeds the CSS in
the generated HTML, producing one atomic `index.html` file.

Site-specific CSS changes belong in the installed configuration copy. Upgrades
preserve that copy unless `--force-config` is specified.
