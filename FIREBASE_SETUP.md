# Firebase 数据库接入步骤（Flutter）

## 1) 安装依赖
在 `pubspec.yaml` 添加（或确认已存在）：

- `firebase_core`
- `firebase_auth`
- `cloud_firestore`

## 2) 连接 Firebase 项目
1. 安装 FlutterFire CLI：
   - `dart pub global activate flutterfire_cli`
2. 在项目根目录执行：
   - `flutterfire configure`
3. 该命令会生成 `lib/firebase_options.dart`，并把平台配置写入 Android / iOS 工程。

## 3) 初始化 Firebase
本项目当前在 `lib/main.dart` 使用 `Firebase.initializeApp()` 初始化。
如果你已经生成了 `firebase_options.dart`，推荐改成：

```dart
await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);
```

## 4) 写入 Firestore（用户资料）
当前注册流程已封装到 `lib/firebase/user_repository.dart`：

- 集合：`users`
- 文档 ID：`uid`
- 字段：`uid/email/name/createdAt/updatedAt`

`register_page.dart` 在注册成功后会调用该仓库写入用户资料。

## 5) Firestore 安全规则（开发期示例）
在 Firebase Console > Firestore Rules 可以先用：

```txt
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

> 生产环境请继续细化规则（字段校验、管理员角色、只读字段限制等）。
