<script setup lang="ts">
import zhCN from 'element-plus/es/locale/lang/zh-cn'
</script>

<template>
  <!-- 全局注入 Element Plus 中文语言包，统一分页 / 日期选择 / 确认框等内置文案 -->
  <el-config-provider :locale="zhCN">
    <router-view />
  </el-config-provider>
</template>