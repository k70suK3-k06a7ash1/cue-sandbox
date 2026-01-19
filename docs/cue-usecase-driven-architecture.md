# CUE とユースケース駆動アーキテクチャ

CUE のデータ駆動アプローチとユースケース駆動アーキテクチャ（Clean Architecture, Hexagonal Architecture）の相性について。

## 相性が良い理由

| ユースケース駆動の特徴 | CUE の強み |
|----------------------|-----------|
| 境界の明確化 | スキーマによる入出力定義 |
| ドメインロジック分離 | 制約をコードから分離 |
| テスタビリティ | 設定の検証が独立して可能 |
| 依存性の方向制御 | 設定とロジックの分離 |

## アーキテクチャ概要

```
┌─────────────────────────────────────────────────────────┐
│                      External Layer                      │
│  (HTTP, CLI, Message Queue)                             │
└────────────────────────┬────────────────────────────────┘
                         │
                    CUE 検証 (Input)
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                      Use Case Layer                      │
│  (Application Business Rules)                           │
└────────────────────────┬────────────────────────────────┘
                         │
                    CUE 検証 (Output)
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                   Infrastructure Layer                   │
│  (Database, External API, File System)                  │
└─────────────────────────────────────────────────────────┘
```

## 具体的な活用パターン

### ディレクトリ構成例

```
src/
├── usecases/
│   ├── create_user.go
│   ├── update_order.go
│   └── process_payment.go
├── schemas/              # CUE スキーマ
│   ├── inputs.cue        # ユースケース入力 DTO
│   ├── outputs.cue       # ユースケース出力 DTO
│   ├── domain.cue        # ドメインモデル制約
│   └── events.cue        # ドメインイベント
├── config/
│   └── app.cue           # アプリケーション設定
└── infrastructure/
    └── schemas/
        └── external.cue  # 外部 API レスポンス検証
```

### 1. 境界でのバリデーション (Input/Output DTO)

```cue
// schemas/inputs.cue
package schemas

// ユーザー作成の入力制約
#CreateUserInput: {
    name:  string & =~"^[a-zA-Z]{2,50}$"
    email: string & =~"^.+@.+\\..+$"
    age:   int & >=0 & <=150
}

// 注文作成の入力制約
#CreateOrderInput: {
    userId:   string & =~"^[a-z0-9-]{36}$"
    items:    [...#OrderItemInput] & [_, ...]  // 最低1件
    coupon?: string
}

#OrderItemInput: {
    productId: string
    quantity:  int & >=1 & <=100
}
```

```cue
// schemas/outputs.cue
package schemas

// ユーザー作成の出力
#CreateUserOutput: {
    id:        string
    name:      string
    email:     string
    createdAt: string
}

// 注文作成の出力
#CreateOrderOutput: {
    orderId:   string
    total:     number & >=0
    status:    #OrderStatus
    createdAt: string
}

#OrderStatus: "pending" | "confirmed" | "processing" | "shipped" | "delivered"
```

### 2. ドメインモデルの制約定義

```cue
// schemas/domain.cue
package schemas

import "list"

// ドメインエンティティ: Order
#Order: {
    id:       string
    userId:   string
    items:    [...#OrderItem] & list.MinItems(1)
    subtotal: number & >=0
    discount: number & >=0 & <=subtotal  // 割引は小計以下
    total:    number & >=0
    status:   #OrderStatus

    // ビジネスルール: total = subtotal - discount
    total: subtotal - discount
}

#OrderItem: {
    productId:   string
    productName: string
    unitPrice:   number & >=0
    quantity:    int & >=1
    lineTotal:   number & >=0

    // 計算制約
    lineTotal: unitPrice * quantity
}

// ドメインエンティティ: User
#User: {
    id:        string
    name:      string & =~"^.{2,50}$"
    email:     string
    status:    "active" | "inactive" | "suspended"
    createdAt: string
    updatedAt: string
}
```

### 3. ドメインイベントの定義

```cue
// schemas/events.cue
package schemas

#DomainEvent: {
    eventId:   string
    eventType: string
    timestamp: string
    payload:   _
}

#UserCreatedEvent: #DomainEvent & {
    eventType: "user.created"
    payload: {
        userId: string
        email:  string
    }
}

#OrderPlacedEvent: #DomainEvent & {
    eventType: "order.placed"
    payload: {
        orderId: string
        userId:  string
        total:   number
    }
}
```

### 4. 設定ファイルの検証

```cue
// config/app.cue
package config

#AppConfig: {
    server: {
        host: string | *"localhost"
        port: int & >=1 & <=65535 | *8080
    }
    database: {
        host:     string
        port:     int | *5432
        name:     string
        user:     string
        password: string
        pool: {
            maxConns: int & >=1 | *10
            minConns: int & >=0 | *2
        }
    }
    features: {
        enableCache:    bool | *true
        enableMetrics:  bool | *true
        rateLimitPerSec: int & >=0 | *100
    }
}

// 実際の設定値
config: #AppConfig & {
    server: {
        host: "0.0.0.0"
        port: 3000
    }
    database: {
        host:     "db.example.com"
        name:     "myapp"
        user:     "app_user"
        password: string  // 環境変数から注入
    }
}
```

## 検証コマンド例

```bash
# 入力データの検証
cue vet schemas/inputs.cue request.json -d '#CreateUserInput'

# 設定ファイルの検証
cue vet config/app.cue config.yaml

# スキーマのエクスポート (OpenAPI)
cue export schemas/inputs.cue --out openapi

# JSON Schema 生成
cue export schemas/domain.cue --out jsonschema
```

## メリットまとめ

1. **関心の分離**: ビジネスロジック（Go/TS）と制約定義（CUE）を分離
2. **型安全性**: 境界でのデータ検証を宣言的に定義
3. **ドキュメント化**: スキーマがそのまま仕様書になる
4. **テスト容易性**: 制約の検証をユニットテストから独立
5. **再利用性**: 同一スキーマを複数レイヤーで活用
6. **進化可能性**: スキーマの後方互換性を `cue` でチェック可能

## 参考リンク

- [CUE 公式サイト](https://cuelang.org/)
- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [Hexagonal Architecture](https://alistair.cockburn.us/hexagonal-architecture/)
