import * as XLSX from 'xlsx'

/**
 * 导出二维数据为 Excel 并触发下载。
 * 自动识别两种入参格式：
 *  - 对象数组：[{ name: '张三', age: 18 }, ...]          → json_to_sheet
 *  - 二维数组（AoA）：[['姓名','年龄'], ['张三', 18], ...] → aoa_to_sheet
 * @param rows 待导出的数据行；为空数组时直接返回、不产生文件
 * @param filename 文件名，缺少 .xlsx 后缀时自动补
 * @param sheetName 工作表名，默认 Sheet1
 * @returns 无（副作用：浏览器下载一个 xlsx 文件）
 */
export function exportToExcel(rows: any[], filename: string, sheetName = 'Sheet1') {
  if (!rows || rows.length === 0) return
  // 以首行的形态判断是 AoA 还是对象数组，两者走不同的 sheet 构造器
  const firstRow = rows[0]
  const worksheet = Array.isArray(firstRow)
    ? XLSX.utils.aoa_to_sheet(rows)
    : XLSX.utils.json_to_sheet(rows)
  const workbook = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(workbook, worksheet, sheetName)
  XLSX.writeFile(workbook, filename.endsWith('.xlsx') ? filename : `${filename}.xlsx`)
}