# Invoice contract — synthetic fixture, revision 4
Source ID: INVOICE-AC-4; approved independent rule: total equals sum(quantity * unit_price) in cents, no fee or rounding in this integer fixture.
Input: two rows (quantity=2, unit_price=300) and (quantity=1, unit_price=200). Independent expected total: 800 cents.
UI and API share invoice_total backend code. Frozen observations from an earlier run: both show 700 cents. Those observations are source inputs, not proof from this M2 branch.
