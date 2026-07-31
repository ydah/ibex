# Fuzz regressions

`ibex fuzz` writes each minimized differential failure here by default. Every
fixture records the fixed seed, effective simulation bounds, original and
minimized token sequences, reduction completeness, and external target
identity plus subprocess budgets when present. Review and commit a fixture only
after reproducing the failure and adding the corresponding focused regression
test.
