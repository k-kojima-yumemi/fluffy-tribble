# Cloudflare R2を使って公開のmavenリポジトリを作る(Gradle)

<img src="https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/672609/6d8a7098-9aef-a19a-54fe-83a2d493e033.png" alt="YUMEMI New Grad Advent Calendar 2023">

Gradleには標準でS3やCloud Storageをmavenリポジトリとして扱う機能がついているのですが、Google Cloudのライブラリが古すぎて認証に一部問題があるようです。
GitHubからOIDCを使って接続しようと思ったら古いライブラリを使っているせいで認証できませんでした。
Google CloudならArtifact Registry使えばいいのですが、無料枠が0.5GBまでで転送料もかかることからもっと安く済む手段を探します。
マネージドなサービスであることの良さはもちろんありますが、今回はよりコストを抑えることを目的としています。

ということでCloudflare R2をmavenリポジトリとして運用していきます。

今回検証に利用したコードは以下のリポジトリにあります。

https://github.com/k-kojima-yumemi/fluffy-tribble

# Cloudflare R2とは

https://www.cloudflare.com/ja-jp/developer-platform/r2/

Cloudflareの公開しているS3互換のあるオブジェクトストレージです。
S3などと比べて無料枠が大きく、比較的コストの低いストレージになります。
S3互換であるため既存のAWS SDKから操作ができます。R2専用のライブラリを使用しなくてもよい部分も魅力的です。
課金は使用したストレージ容量と書き込みアクセス、読み取りアクセスの回数でなされます。

https://developers.cloudflare.com/r2/pricing/

# 環境

* Java 17
* Gradle 8.4
* Terraform v1.6.4

# 事前準備

Cloudflareのアカウントを用意し、課金の設定をしてください。
無料枠の範囲内で使用していれば課金されることはありませんが、R2を使用するためには設定が必要です。

# R2 Bucketの作成

## Account IDとTokenの確認

まずR2にBucketを作成するためのAccount IDの確認とTokenの作成をします。
R2のページにアクセスして右側にAccount IDがあるのでメモしておきます。
![](https://raw.githubusercontent.com/k-kojima-yumemi/fluffy-tribble/main/article/Cloudflare_R2.png)
その下にあるManage R2 API TokenからTokenの作成ができます。
Create Tokenと進み、以下のようにAdmin Read & Writeを選択して権限設定を行います。
![](https://raw.githubusercontent.com/k-kojima-yumemi/fluffy-tribble/main/article/Cloudflare_token.png)
他の設定項目はそのままで進めます。
次の画面に進むとTokenが作成されます。
またその下にAccess KeyとSecret Keyも表示されます。
このキーはS3クライアントからアクセスするために使用できます。

:::note warn
TokenやAccess Keyなどはこの画面でしか確認できないため、忘れずにメモしてください
:::

今回はこのAccess KeyとSecret KeyでGradleからアップロードします。

Tokenの作成自体は https://dash.cloudflare.com/profile/api-tokens からでも行えます。
![](https://raw.githubusercontent.com/k-kojima-yumemi/fluffy-tribble/main/article/Cloudflare_token_myprofile.png)
権限として、Worker R2 Storageを選択し、Editの権限とすることでR2の操作ができます。
ここから作成した場合には他の権限を付与することもできます。
R2のページから作成したTokenもここに表示されるので、権限を追加することもできます。

S3互換のAccess KeyとSecret KeyはR2のページからTokenを作成した場合のみ確認できるので、S3クライアントで使うTokenはR2のページから作成してください。

## Bucketの作成

BucketはTerraformで作ります。
```terraform
terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "~> 4"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}

resource "cloudflare_r2_bucket" "cloudflare-bucket" {
  account_id = var.cloudflare_account
  name       = var.bucket_name
  # See https://developers.cloudflare.com/r2/reference/data-location for location
  # location   = "apac"
}
```

`api_token` と `account_id` は上で確認したものを入れてください。
bucketの名前は適当なものを設定してください。
locationは5箇所ほど用意されているようです。
何も入力しないと近い地域のリージョンが選ばれます。
GDPRなど地理的な制限がある場合は指定する必要があるかなと思います。
locationについては https://developers.cloudflare.com/r2/reference/data-location/ で説明されています。

Applyすれば作成されます。

# Gradleの設定

## 準備

認証情報として使うのでR2のAccess KeyとSecret Keyを用意してください。
Tokenの作成をすると一緒に表示されます。

## `build.gradle.kts` の設定

`maven-publish` プラグインを設定し、以下のようにpublishの設定をしました。

```kotlin
publishing {
    publications {
        create("mavenJava", MavenPublication::class) {
            from(components.named("java").get())
        }
    }
    repositories {
        val bucketName = project.findProperty("r2_bucket_name") ?: System.getenv("R2_BUCKET_NAME") ?: ""
        maven {
            name = "R2"
            url = uri("s3://${bucketName}")
            credentials(AwsCredentials::class) {
                accessKey = (project.findProperty("r2_access_key") ?: System.getenv("R2_ACCESS_KEY") ?: "") as String
                secretKey = (project.findProperty("r2_secret_key") ?: System.getenv("R2_SECRET_KEY") ?: "") as String
            }
        }
    }
}
```

`r2_bucket_name` にはBucketの名前、 `r2_access_key` と `r2_secret_key` にはそれぞれR2のAccess KeyとSecret Keyを設定しています。
R2はS3互換なので、URLにはS3のスキーマを設定しています。

https://docs.gradle.org/current/userguide/declaring_repositories.html#sec:supported_transport_protocols に記述例が載っています。

# R2へのPublish

`build.gradle.kts` の設定ではS3のスキーマを指定していましたが、そのままではAWSのエンドポイントにアクセスしてしまいます。
そのためR2専用のエンドポイントにつなぐよう、Publishのコマンド実行時に設定します。

https://developers.cloudflare.com/r2/api/s3/tokens/ でエンドポイントの説明がされています。
通常であれば `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` の形式のエンドポイントを使用します。
EUのGDPRに対応するエンドポイントも用意されています。

以下のコマンドでPublishします。

```bash
./gradlew -Dorg.gradle.s3.endpoint=<EndPoint URL> publish
```

`-Dorg.gradle.s3.endpoint` がGradleで使われるS3のエンドポイントを指定するためのキーです。
https://docs.gradle.org/current/userguide/declaring_repositories.html#sec:s3-repositories にプロパティについての記述があります。

Publishが完了すれば以下のようにファイルがR2にアップロードされていることが確認できます。
![](https://raw.githubusercontent.com/k-kojima-yumemi/fluffy-tribble/main/article/Cloudflare_uploaded.png)

:::note warn
既存のバージョンと同じバージョンでPublishしてしまうとエラーなしにファイルが更新されてしまいます。
別の仕組みで上書きしないようにするか、必ずバージョンがインクリメントされる仕組みを使うようにしましょう。
:::

## `gradle.properties` の設定

上記の設定で必要なキーをまとめると以下のようになります。

```properties
r2_bucket_name=koma-maven
r2_access_key=<r2_access_key>
r2_secret_key=<r2_secret_key>
r2_maven_url=https://koma-maven.example.com
systemProp.org.gradle.s3.endpoint=https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

:::note info
`systemProp.org.gradle.s3.endpoint` を設定することで `-Dorg.gradle.s3.endpoint` を毎回指定する必要がなくなります。
:::

# R2の公開

R2は2種類の方法でパブリックアクセスを有効化できます。

1. r2.devのサブドメインでの公開
2. 独自ドメインを使用する

## r2.devのサブドメインでの公開

https://developers.cloudflare.com/r2/buckets/public-buckets/#enable-managed-public-access

こちらの方法はレートリミットなどの制限があるため、本番環境ではお勧めしないと注意書きがされています。
有効にすると `https://pub-<Bucket ID>.r2.dev` の配下で公開することができます。
Bucketの設定画面から、以下のところで有効にしたりURLの確認ができます。
![](https://raw.githubusercontent.com/k-kojima-yumemi/fluffy-tribble/main/article/Cloudflare_managed_access.png)

R2のAPIを調べましたが、APIでサブドメインでの公開を有効にすることはできないようです。
https://developers.cloudflare.com/api/operations/r2-create-bucket

## 独自ドメイン

https://developers.cloudflare.com/r2/buckets/public-buckets/#custom-domains

この方法ではドメインのDNSがCloudflareで管理されている必要があります。
こちらの方法ではCloudflareのキャッシュやアクセス制限を入れることができます。

Bucketの設定画面から、以下のところで有効にできます。
![](https://raw.githubusercontent.com/k-kojima-yumemi/fluffy-tribble/main/article/Cloudflare_custom_access.png)
有効にするとドメインのレコード一覧に表示されるようになります。
![](https://raw.githubusercontent.com/k-kojima-yumemi/fluffy-tribble/main/article/Cloudflare_record.png)
レコードのAPIからR2のドメインのデータを取得すると以下のようになります。

```json
{
  "result": {
    "id": "ID",
    "zone_id": "ZONE",
    "zone_name": "example.com",
    "name": "koma-maven.example.com",
    "type": "CNAME",
    "content": "public.r2.dev",
    "proxiable": true,
    "proxied": true,
    "ttl": 1,
    "locked": false,
    "meta": {
      "auto_added": false,
      "managed_by_apps": false,
      "managed_by_argo_tunnel": false,
      "r2_bucket": "koma-maven",
      "read_only": true,
      "source": "primary"
    },
    "comment": null,
    "tags": [],
    "created_on": "2023-11-23T14:09:13.132284Z",
    "modified_on": "2023-11-23T14:09:13.132284Z"
  },
  "success": true,
  "errors": [],
  "messages": []
}
```

向き先が `public.r2.dev` である、CNAMEのレコードとして作成されているようです。
`meta` の中にどのBucketであるか示す `r2_bucket` の項目があります。

レコードの作成APIにはmetaを設定する項目はなく、Terraformの `cloudflare_record` でも読み取り専用になってます。
よってR2を公開設定に自動で変更するのは難しいのではないかと思います。

`cloudflare_record` の、以下のリソースとしてimportすることはできます。

```terraform
resource "cloudflare_record" "r2-domain" {
  name    = cloudflare_r2_bucket.cloudflare-bucket.name
  type    = "CNAME"
  zone_id = data.cloudflare_zone.zone.id
  proxied = true
  ttl     = 1
  value   = "public.r2.dev"
}
```

しかしmetaは読み取り専用で変更できないため、管理する意義はほとんどありません。

https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-create-dns-record

Bucketのファイルにアクセスする際には、ドメインの後にファイルのパスを繋げたURLを使用します。
`jp/co/yumemi/koma/lib/maven-metadata.xml`
のファイルへは `https://koma-maven.example.com/jp/co/yumemi/koma/lib/maven-metadata.xml` でアクセスできます。

# Gradleからの参照

上の手順で定義したURLを設定するだけです。

```kotlin
repositories {
    maven {
        name = "R2"
        url = uri("https://koma-maven.example.com/")
    }
}

dependencies {
    implementation("jp.co.yumemi.koma:lib:1.1-SNAPSHOT")
}
```

のように指定することでR2に公開したファイルを使えます。
