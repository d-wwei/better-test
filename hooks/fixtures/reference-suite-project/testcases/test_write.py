import pytest


def _place(ctx):
    return ctx.place_order("US.AAPL")


@pytest.mark.integration
def test_write_through_helper(trade_ctx):
    _place(trade_ctx)


def test_dynamic_skip(value):
    pytest.skip(f"{value} 无数据")
