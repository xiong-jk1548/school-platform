import * as XLSX from 'xlsx'

/**
 * 导出 Excel
 * 支持两种数据格式：
 *  - 对象数组：[{ name: '张三', age: 18 }, ...]   → json_to_sheet
 *  - 二维数组（AoA）：[['姓名','年龄'], ['张三', 18], ...] → aoa_to_sheet
 */
export function exportToExcel(data: any[], filename: string, sheetName = 'Sheet1') {
  if (!data || data.length === 0) return
  const first = data[0]
  const worksheet = Array.isArray(first)
    ? XLSX.utils.aoa_to_sheet(data)
    : XLSX.utils.json_to_sheet(data)
  const workbook = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(workbook, worksheet, sheetName)
  XLSX.writeFile(workbook, filename.endsWith('.xlsx') ? filename : `${filename}.xlsx`)
}
