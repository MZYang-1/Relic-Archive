# 技术架构与设计文档

## 1. 整体架构概览

采用经典的移动端应用架构，通过 API 网关与后端服务交互。核心计算（如 AI 描述生成、图像处理）在云端进行，部分实时性要求高的轻量级处理（如拍摄引导、基础滤镜）在端侧完成。

```mermaid
graph TD
    User[用户 (App)] --> API_Gateway[API 网关]
    API_Gateway --> Auth_Service[认证与隐私服务]
    API_Gateway --> Core_Service[核心业务服务]
    API_Gateway --> AI_Service[AI 服务层]
    
    subgraph "后端服务"
    Auth_Service --> DB[(用户数据库)]
    Core_Service --> DB
    Core_Service --> Object_Store[(对象存储 - 图片/模型)]
    AI_Service --> Image_Process[图像处理服务]
    AI_Service --> LLM_Engine[LLM 描述生成引擎]
    end
    
    subgraph "端侧 (App)"
    Camera[相机模块 (Metal/Camera2)]
    Local_Store[本地加密存储]
    Rendering[渲染引擎 (SceneKit/OpenGL)]
    end
```

## 2. 技术选型建议

### 2.1 移动端 (App)
- **方案 A (原生开发 - 推荐)**：
    - **iOS**: Swift + SwiftUI + Metal (用于高性能图像处理)。
    - **Android**: Kotlin + Jetpack Compose + CameraX。
    - **理由**：能够最大程度调用相机硬件能力，提供流畅的动画和 3D 渲染体验。
- **方案 B (跨平台)**：
    - **Flutter**: 适合快速开发，但在高性能 3D 和复杂相机交互上可能需要编写原生插件。
    - **React Native**: 社区成熟，适合 Web 前端背景团队。

### 2.2 后端服务
- **语言**: Python (FastAPI/Django) 或 Go (Gin)。Python 在 AI 库集成上更有优势。
- **数据库**: PostgreSQL (关系型数据) + MongoDB (非结构化描述/日志)。
- **存储**: AWS S3 / 阿里云 OSS / MinIO (自建)。

### 2.3 AI 与算法栈
- **图像识别/分类**: PyTorch, YOLOv8 (物体检测), MobileNet (轻量级分类)。
- **描述生成 (LLM)**: OpenAI GPT-4o / Claude 3.5 Sonnet (API 调用) 或部署开源模型 (Llama 3, Mistral) 用于成本控制。
- **3D/视差处理**: OpenCV (基础图像处理), NeRF (未来规划), Three.js/Babylon.js (Web 端展示)。

## 3. 核心功能技术实现

### 3.1 图像采集与处理
- **端侧**：
    - 使用原生相机 API 获取高分辨率图像流。
    - 实时计算图像锐度，提示用户是否模糊。
    - 陀螺仪数据记录，辅助后续拼接或 3D 视差计算。
- **云端**：
    - 接收上传的原图，生成多级缩略图。
    - 异步调用 AI 服务进行分析。

### 3.2 AI 描述生成流水线
1.  **输入**：用户上传的图片 + 语音备注/文字备注。
2.  **视觉分析 (Vision Model)**：提取特征（颜色、材质、物体名称、磨损程度）。
3.  **Prompt 构建**：将视觉特征 + 用户备注 + 选定风格（如“私密日记”）组合成 Prompt。
4.  **LLM 生成**：调用 LLM 生成结构化 JSON 数据（包含：标题、故事文本、情绪标签、估值等）。
5.  **输出**：返回给 App 展示，用户可微调。

### 3.3 隐私与安全
- **数据加密**：
    - 数据库敏感字段（如私密日记）使用 AES-256 加密存储。
    - 传输层全链路 HTTPS。
- **本地安全**：
    - App 启动支持 Biometric Auth (FaceID/TouchID)。
    - 本地缓存数据加密存储 (iOS Keychain / Android Keystore)。

## 4. 数据模型设计 (简化版)

### 4.1 Item (物品)
```json
{
  "id": "uuid",
  "user_id": "uuid",
  "images": ["url1", "url2", "url3"],
  "video": "url_optional",
  "category": "string", // 自动分类结果
  "tags": ["tag1", "tag2"], // 情绪标签、物理标签
  "ai_description": {
    "summary": "...",
    "story": "...",
    "material": "...",
    "era_guess": "..."
  },
  "user_notes": "...",
  "status": "active/archived/hidden",
  "created_at": "timestamp",
  "updated_at": "timestamp"
}
```

### 4.2 Collection (收藏馆)
```json
{
  "id": "uuid",
  "user_id": "uuid",
  "name": "我的童年",
  "theme": "nostalgia", // 主题风格
  "items": ["item_id_1", "item_id_2"],
  "is_private": true
}
```

## 5. 原型页面结构 (MVP)

- **首页 (Home)**
    - 顶部：搜索栏、筛选。
    - 中部：今日记录（卡片式）、最近浏览。
    - 底部 FAB：开始记录（相机入口）。
- **拍摄页 (Camera)**
    - 取景框（含辅助线）。
    - 底部：拍照按钮、模式切换（照片/视频）。
    - 引导提示层。
- **详情页 (Item Detail)**
    - 顶部：大图/伪 3D 视窗。
    - 中部：AI 故事卡片（可展开）。
    - 底部：属性标签、编辑按钮、分享/归档。
- **收藏馆 (Gallery)**
    - 网格视图 / 瀑布流。
    - 文件夹管理。
