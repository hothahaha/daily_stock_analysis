# -*- coding: utf-8 -*-
"""
Tushare 旧版实时接口 symbol 路由测试

目标：确保裸 6 位代码不会被隐式映射为指数 symbol。
"""
import os
import sys
import unittest

# 确保可按包路径导入 data_provider（支持相对导入）
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from data_provider.tushare_fetcher import _to_legacy_realtime_symbol


class TestTushareLegacyRealtimeSymbol(unittest.TestCase):
    """_to_legacy_realtime_symbol 的行为验证"""

    def test_plain_000001_keeps_stock_semantics(self):
        """裸 000001 必须按个股处理，不能隐式映射为 sh000001。"""
        self.assertEqual(_to_legacy_realtime_symbol("000001"), "000001")

    def test_explicit_index_codes_are_mapped(self):
        """显式指数写法应映射到旧版接口需要的 symbol。"""
        self.assertEqual(_to_legacy_realtime_symbol("000001.SH"), "sh000001")
        self.assertEqual(_to_legacy_realtime_symbol("sh000001"), "sh000001")
        self.assertEqual(_to_legacy_realtime_symbol("SZ399001"), "sz399001")

    def test_common_stock_prefix_suffix_are_normalized_to_base_code(self):
        """普通股票前后缀写法应归一到 6 位基础代码。"""
        self.assertEqual(_to_legacy_realtime_symbol("SZ000001"), "000001")
        self.assertEqual(_to_legacy_realtime_symbol("600519.SH"), "600519")


if __name__ == "__main__":
    unittest.main()
