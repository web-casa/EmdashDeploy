#!/usr/bin/env bash

normalize_install_lang() {
	local input="${1:-en}"
	input="${input//_/-}"
	case "${input,,}" in
	en | english) printf 'en\n' ;;
	ja | jp | japanese) printf 'ja\n' ;;
	ko | korean) printf 'ko\n' ;;
	es | spanish | espanol | español) printf 'es\n' ;;
	de | german | deutsch) printf 'de\n' ;;
	fr | french | francais | français) printf 'fr\n' ;;
	zh-cn | zh-hans | zh-sg | zh) printf 'zh-CN\n' ;;
	zh-tw | zh-hant | zh-hk) printf 'zh-TW\n' ;;
	pt | pt-br | pt-pt | portuguese | portugues | português) printf 'pt\n' ;;
	*) printf 'en\n' ;;
	esac
}

detect_install_lang() {
	local basename_lang=""
	local script_name
	script_name="$(basename "${0}")"
	if [[ -z "${EMDASH_INSTALL_LANG:-}" ]]; then
		case "${script_name}" in
		install-emdash.*.sh)
			basename_lang="${script_name#install-emdash.}"
			basename_lang="${basename_lang%.sh}"
			EMDASH_INSTALL_LANG="$(normalize_install_lang "${basename_lang}")"
			;;
		*)
			EMDASH_INSTALL_LANG="en"
			;;
		esac
	else
		EMDASH_INSTALL_LANG="$(normalize_install_lang "${EMDASH_INSTALL_LANG}")"
	fi
	export EMDASH_INSTALL_LANG
}

default_timezone_for_lang() {
	local lang="${EMDASH_INSTALL_LANG:-en}"
	case "${lang}" in
	en) printf 'America/New_York\n' ;;
	ja) printf 'Asia/Tokyo\n' ;;
	ko) printf 'Asia/Seoul\n' ;;
	es) printf 'Europe/Madrid\n' ;;
	de) printf 'Europe/Berlin\n' ;;
	fr) printf 'Europe/Paris\n' ;;
	zh-CN) printf 'Asia/Shanghai\n' ;;
	zh-TW) printf 'Asia/Taipei\n' ;;
	pt) printf 'America/Sao_Paulo\n' ;;
	*) printf 'UTC\n' ;;
	esac
}

ti() {
	local key="$1"
	local lang="${EMDASH_INSTALL_LANG:-en}"
	case "${key}" in
	default_word)
		case "${lang}" in
		en) printf 'default' ;;
		ja) printf '既定' ;;
		ko) printf '기본값' ;;
		es) printf 'predeterminado' ;;
		de) printf 'Standard' ;;
		fr) printf 'par défaut' ;;
		zh-CN) printf '默认' ;;
		zh-TW) printf '預設' ;;
		pt) printf 'padrão' ;;
		esac
		;;
	set_word)
		case "${lang}" in
		en) printf '(set)' ;;
		ja) printf '(設定済み)' ;;
		ko) printf '(설정됨)' ;;
		es) printf '(configurado)' ;;
		de) printf '(gesetzt)' ;;
		fr) printf '(défini)' ;;
		zh-CN) printf '(已设置)' ;;
		zh-TW) printf '(已設定)' ;;
		pt) printf '(definido)' ;;
		esac
		;;
	blank_word)
		case "${lang}" in
		en) printf '(blank)' ;;
		ja) printf '(空欄)' ;;
		ko) printf '(비워 둠)' ;;
		es) printf '(vacío)' ;;
		de) printf '(leer)' ;;
		fr) printf '(vide)' ;;
		zh-CN) printf '(留空)' ;;
		zh-TW) printf '(留空)' ;;
		pt) printf '(em branco)' ;;
		esac
		;;
	enter_y_or_n)
		case "${lang}" in
		en) printf 'Please enter y or n.' ;;
		ja) printf 'y または n を入力してください。' ;;
		ko) printf 'y 또는 n 을 입력하세요.' ;;
		es) printf 'Introduce y o n.' ;;
		de) printf 'Bitte y oder n eingeben.' ;;
		fr) printf 'Veuillez saisir y ou n.' ;;
		zh-CN) printf '请输入 y 或 n。' ;;
		zh-TW) printf '請輸入 y 或 n。' ;;
		pt) printf 'Digite y ou n.' ;;
		esac
		;;
	choose_one_of)
		case "${lang}" in
		en) printf 'Please enter one of:' ;;
		ja) printf '次のいずれかを入力してください:' ;;
		ko) printf '다음 중 하나를 입력하세요:' ;;
		es) printf 'Introduce una de estas opciones:' ;;
		de) printf 'Bitte einen der folgenden Werte eingeben:' ;;
		fr) printf 'Veuillez saisir une des valeurs suivantes :' ;;
		zh-CN) printf '请输入以下之一:' ;;
		zh-TW) printf '請輸入以下之一:' ;;
		pt) printf 'Digite uma destas opções:' ;;
		esac
		;;
	unknown_arg)
		case "${lang}" in
		en) printf 'Unknown argument:' ;;
		ja) printf '不明な引数:' ;;
		ko) printf '알 수 없는 인수:' ;;
		es) printf 'Argumento desconocido:' ;;
		de) printf 'Unbekanntes Argument:' ;;
		fr) printf 'Argument inconnu :' ;;
		zh-CN) printf '未知参数:' ;;
		zh-TW) printf '未知參數:' ;;
		pt) printf 'Argumento desconhecido:' ;;
		esac
		;;
	require_root)
		case "${lang}" in
		en) printf 'Please run the installer as root.' ;;
		ja) printf 'インストーラーは root で実行してください。' ;;
		ko) printf '설치 프로그램을 root로 실행하세요.' ;;
		es) printf 'Ejecuta el instalador como root.' ;;
		de) printf 'Bitte führe den Installer als root aus.' ;;
		fr) printf 'Veuillez exécuter l’installateur en tant que root.' ;;
		zh-CN) printf '请使用 root 运行安装器。' ;;
		zh-TW) printf '請使用 root 執行安裝器。' ;;
		pt) printf 'Execute o instalador como root.' ;;
		esac
		;;
	non_interactive_mode)
		case "${lang}" in
		en) printf 'Non-interactive mode: using environment variables and defaults' ;;
		ja) printf '非対話モード: 環境変数と既定値を使用します' ;;
		ko) printf '비대화형 모드: 환경 변수와 기본값을 사용합니다' ;;
		es) printf 'Modo no interactivo: usando variables de entorno y valores predeterminados' ;;
		de) printf 'Nicht-interaktiver Modus: Umgebungsvariablen und Standardwerte werden verwendet' ;;
		fr) printf 'Mode non interactif : utilisation des variables d’environnement et des valeurs par défaut' ;;
		zh-CN) printf '非交互模式，使用环境变量和默认值' ;;
		zh-TW) printf '非互動模式，使用環境變數與預設值' ;;
		pt) printf 'Modo não interativo: usando variáveis de ambiente e valores padrão' ;;
		esac
		;;
	project_name) case "${lang}" in en) printf 'Project name' ;; ja) printf 'プロジェクト名' ;; ko) printf '프로젝트 이름' ;; es) printf 'Nombre del proyecto' ;; de) printf 'Projektname' ;; fr) printf 'Nom du projet' ;; zh-CN) printf '项目名' ;; zh-TW) printf '專案名稱' ;; pt) printf 'Nome do projeto' ;; esac ;;
	template) case "${lang}" in en) printf 'Template' ;; ja) printf 'テンプレート' ;; ko) printf '템플릿' ;; es) printf 'Plantilla' ;; de) printf 'Template' ;; fr) printf 'Modèle' ;; zh-CN) printf '模板' ;; zh-TW) printf '範本' ;; pt) printf 'Template' ;; esac ;;
	root_dir) case "${lang}" in en) printf 'Install root directory' ;; ja) printf 'インストールルートディレクトリ' ;; ko) printf '설치 루트 디렉터리' ;; es) printf 'Directorio raíz de instalación' ;; de) printf 'Installations-Stammverzeichnis' ;; fr) printf 'Répertoire racine d’installation' ;; zh-CN) printf '安装根目录' ;; zh-TW) printf '安裝根目錄' ;; pt) printf 'Diretório raiz de instalação' ;; esac ;;
	timezone) case "${lang}" in en) printf 'Timezone' ;; ja) printf 'タイムゾーン' ;; ko) printf '시간대' ;; es) printf 'Zona horaria' ;; de) printf 'Zeitzone' ;; fr) printf 'Fuseau horaire' ;; zh-CN) printf '时区' ;; zh-TW) printf '時區' ;; pt) printf 'Fuso horário' ;; esac ;;
	use_caddy) case "${lang}" in en) printf 'Install and configure Caddy' ;; ja) printf 'Caddy をインストールして設定する' ;; ko) printf 'Caddy 설치 및 구성' ;; es) printf 'Instalar y configurar Caddy' ;; de) printf 'Caddy installieren und konfigurieren' ;; fr) printf 'Installer et configurer Caddy' ;; zh-CN) printf '是否安装并配置 Caddy' ;; zh-TW) printf '是否安裝並設定 Caddy' ;; pt) printf 'Instalar e configurar o Caddy' ;; esac ;;
	enable_https) case "${lang}" in en) printf 'Enable HTTPS' ;; ja) printf 'HTTPS を有効にする' ;; ko) printf 'HTTPS 활성화' ;; es) printf 'Habilitar HTTPS' ;; de) printf 'HTTPS aktivieren' ;; fr) printf 'Activer HTTPS' ;; zh-CN) printf '是否启用 HTTPS' ;; zh-TW) printf '是否啟用 HTTPS' ;; pt) printf 'Ativar HTTPS' ;; esac ;;
	domain) case "${lang}" in en) printf 'Site domain' ;; ja) printf 'サイトドメイン' ;; ko) printf '사이트 도메인' ;; es) printf 'Dominio del sitio' ;; de) printf 'Website-Domain' ;; fr) printf 'Domaine du site' ;; zh-CN) printf '站点域名' ;; zh-TW) printf '網站網域' ;; pt) printf 'Domínio do site' ;; esac ;;
	admin_email) case "${lang}" in en) printf 'Caddy / certificate email' ;; ja) printf 'Caddy / 証明書用メール' ;; ko) printf 'Caddy / 인증서 이메일' ;; es) printf 'Correo para Caddy / certificado' ;; de) printf 'E-Mail für Caddy / Zertifikat' ;; fr) printf 'E-mail Caddy / certificat' ;; zh-CN) printf 'Caddy/证书邮箱' ;; zh-TW) printf 'Caddy/憑證郵箱' ;; pt) printf 'E-mail do Caddy / certificado' ;; esac ;;
	https_public_ip_intro) case "${lang}" in en) printf 'Detected public IP for this server' ;; ja) printf 'このサーバーで検出した公開 IP' ;; ko) printf '이 서버에서 감지한 공인 IP' ;; es) printf 'IP pública detectada para este servidor' ;; de) printf 'Erkannte öffentliche IP dieses Servers' ;; fr) printf 'IP publique détectée pour ce serveur' ;; zh-CN) printf '检测到本机公网 IP' ;; zh-TW) printf '偵測到本機公網 IP' ;; pt) printf 'IP público detectado para este servidor' ;; esac ;;
	https_dns_hint) case "${lang}" in en) printf 'Please point your domain to the IP above before continuing.' ;; ja) printf '続行する前に、ドメインを上記の IP に向けてください。' ;; ko) printf '계속하기 전에 도메인을 위 IP로 지정하세요.' ;; es) printf 'Apunta tu dominio a la IP anterior antes de continuar.' ;; de) printf 'Richte deine Domain vor dem Fortfahren auf die obige IP.' ;; fr) printf 'Faites pointer votre domaine vers l’IP ci-dessus avant de continuer.' ;; zh-CN) printf '继续之前，请先将域名解析到上面的 IP。' ;; zh-TW) printf '繼續之前，請先將網域解析到上面的 IP。' ;; pt) printf 'Aponte seu domínio para o IP acima antes de continuar.' ;; esac ;;
	https_dns_confirm) case "${lang}" in en) printf 'Have you finished DNS resolution' ;; ja) printf 'DNS 設定は完了しましたか' ;; ko) printf 'DNS 설정을 완료했나요' ;; es) printf 'Has completado la configuración DNS' ;; de) printf 'Hast du die DNS-Auflösung abgeschlossen' ;; fr) printf 'Avez-vous terminé la configuration DNS' ;; zh-CN) printf '是否已完成域名解析' ;; zh-TW) printf '是否已完成網域解析' ;; pt) printf 'Você concluiu a configuração do DNS' ;; esac ;;
	https_ip_unavailable) case "${lang}" in en) printf 'Public IP detection was inconclusive. Confirm DNS manually before continuing.' ;; ja) printf '公開 IP を確実に判定できませんでした。続行前に DNS を手動で確認してください。' ;; ko) printf '공인 IP를 확실히 판별하지 못했습니다. 계속하기 전에 DNS를 수동으로 확인하세요.' ;; es) printf 'No se pudo determinar con fiabilidad la IP pública. Verifica el DNS manualmente antes de continuar.' ;; de) printf 'Die öffentliche IP konnte nicht zuverlässig erkannt werden. Prüfe DNS vor dem Fortfahren manuell.' ;; fr) printf 'La détection de l’IP publique n’a pas été concluante. Vérifiez le DNS manuellement avant de continuer.' ;; zh-CN) printf '未能可靠识别公网 IP，请在继续前手动确认域名解析。' ;; zh-TW) printf '未能可靠辨識公網 IP，請在繼續前手動確認網域解析。' ;; pt) printf 'A detecção do IP público não foi conclusiva. Confirme o DNS manualmente antes de continuar.' ;; esac ;;
	db_driver) case "${lang}" in en) printf 'Database' ;; ja) printf 'データベース' ;; ko) printf '데이터베이스' ;; es) printf 'Base de datos' ;; de) printf 'Datenbank' ;; fr) printf 'Base de données' ;; zh-CN) printf '数据库' ;; zh-TW) printf '資料庫' ;; pt) printf 'Banco de dados' ;; esac ;;
	pg_db_name) case "${lang}" in en) printf 'PostgreSQL database name' ;; ja) printf 'PostgreSQL データベース名' ;; ko) printf 'PostgreSQL 데이터베이스 이름' ;; es) printf 'Nombre de la base de datos PostgreSQL' ;; de) printf 'PostgreSQL-Datenbankname' ;; fr) printf 'Nom de la base PostgreSQL' ;; zh-CN) printf 'PostgreSQL 数据库名' ;; zh-TW) printf 'PostgreSQL 資料庫名稱' ;; pt) printf 'Nome do banco PostgreSQL' ;; esac ;;
	pg_db_user) case "${lang}" in en) printf 'PostgreSQL username' ;; ja) printf 'PostgreSQL ユーザー名' ;; ko) printf 'PostgreSQL 사용자 이름' ;; es) printf 'Usuario de PostgreSQL' ;; de) printf 'PostgreSQL-Benutzername' ;; fr) printf 'Nom d’utilisateur PostgreSQL' ;; zh-CN) printf 'PostgreSQL 用户名' ;; zh-TW) printf 'PostgreSQL 使用者名稱' ;; pt) printf 'Usuário do PostgreSQL' ;; esac ;;
	pg_db_password) case "${lang}" in en) printf 'PostgreSQL password' ;; ja) printf 'PostgreSQL パスワード' ;; ko) printf 'PostgreSQL 비밀번호' ;; es) printf 'Contraseña de PostgreSQL' ;; de) printf 'PostgreSQL-Passwort' ;; fr) printf 'Mot de passe PostgreSQL' ;; zh-CN) printf 'PostgreSQL 密码' ;; zh-TW) printf 'PostgreSQL 密碼' ;; pt) printf 'Senha do PostgreSQL' ;; esac ;;
	session_driver) case "${lang}" in en) printf 'Session driver' ;; ja) printf 'セッションドライバー' ;; ko) printf '세션 드라이버' ;; es) printf 'Controlador de sesión' ;; de) printf 'Session-Treiber' ;; fr) printf 'Pilote de session' ;; zh-CN) printf 'Session 驱动' ;; zh-TW) printf 'Session 驅動' ;; pt) printf 'Driver de sessão' ;; esac ;;
	redis_password) case "${lang}" in en) printf 'Redis password (optional)' ;; ja) printf 'Redis パスワード (任意)' ;; ko) printf 'Redis 비밀번호(선택 사항)' ;; es) printf 'Contraseña de Redis (opcional)' ;; de) printf 'Redis-Passwort (optional)' ;; fr) printf 'Mot de passe Redis (facultatif)' ;; zh-CN) printf 'Redis 密码(可留空)' ;; zh-TW) printf 'Redis 密碼(可留空)' ;; pt) printf 'Senha do Redis (opcional)' ;; esac ;;
	storage_driver) case "${lang}" in en) printf 'Media storage' ;; ja) printf 'メディアストレージ' ;; ko) printf '미디어 저장소' ;; es) printf 'Almacenamiento de medios' ;; de) printf 'Medienspeicher' ;; fr) printf 'Stockage des médias' ;; zh-CN) printf '媒体存储' ;; zh-TW) printf '媒體儲存' ;; pt) printf 'Armazenamento de mídia' ;; esac ;;
	s3_provider) case "${lang}" in en) printf 'S3 preset' ;; ja) printf 'S3 プリセット' ;; ko) printf 'S3 프리셋' ;; es) printf 'Preajuste S3' ;; de) printf 'S3-Voreinstellung' ;; fr) printf 'Préréglage S3' ;; zh-CN) printf 'S3 预设' ;; zh-TW) printf 'S3 預設' ;; pt) printf 'Predefinição S3' ;; esac ;;
	s3_endpoint) case "${lang}" in en) printf 'S3 endpoint' ;; ja) printf 'S3 エンドポイント' ;; ko) printf 'S3 엔드포인트' ;; es) printf 'Endpoint de S3' ;; de) printf 'S3-Endpunkt' ;; fr) printf 'Endpoint S3' ;; zh-CN) printf 'S3 Endpoint' ;; zh-TW) printf 'S3 Endpoint' ;; pt) printf 'Endpoint S3' ;; esac ;;
	s3_region) case "${lang}" in en) printf 'S3 region' ;; ja) printf 'S3 リージョン' ;; ko) printf 'S3 리전' ;; es) printf 'Región S3' ;; de) printf 'S3-Region' ;; fr) printf 'Région S3' ;; zh-CN) printf 'S3 Region' ;; zh-TW) printf 'S3 Region' ;; pt) printf 'Região S3' ;; esac ;;
	s3_bucket) case "${lang}" in en) printf 'S3 bucket' ;; ja) printf 'S3 バケット' ;; ko) printf 'S3 버킷' ;; es) printf 'Bucket de S3' ;; de) printf 'S3-Bucket' ;; fr) printf 'Bucket S3' ;; zh-CN) printf 'S3 Bucket' ;; zh-TW) printf 'S3 Bucket' ;; pt) printf 'Bucket S3' ;; esac ;;
	s3_access_key) case "${lang}" in en) printf 'S3 access key ID' ;; ja) printf 'S3 Access Key ID' ;; ko) printf 'S3 Access Key ID' ;; es) printf 'Access Key ID de S3' ;; de) printf 'S3 Access Key ID' ;; fr) printf 'Access Key ID S3' ;; zh-CN) printf 'S3 Access Key ID' ;; zh-TW) printf 'S3 Access Key ID' ;; pt) printf 'Access Key ID do S3' ;; esac ;;
	s3_secret_key) case "${lang}" in en) printf 'S3 secret access key' ;; ja) printf 'S3 Secret Access Key' ;; ko) printf 'S3 Secret Access Key' ;; es) printf 'Secret Access Key de S3' ;; de) printf 'S3 Secret Access Key' ;; fr) printf 'Secret Access Key S3' ;; zh-CN) printf 'S3 Secret Access Key' ;; zh-TW) printf 'S3 Secret Access Key' ;; pt) printf 'Secret Access Key do S3' ;; esac ;;
	s3_public_url) case "${lang}" in en) printf 'S3 public URL (optional)' ;; ja) printf 'S3 公開 URL (任意)' ;; ko) printf 'S3 공개 URL(선택 사항)' ;; es) printf 'URL pública de S3 (opcional)' ;; de) printf 'Öffentliche S3-URL (optional)' ;; fr) printf 'URL publique S3 (facultatif)' ;; zh-CN) printf 'S3 Public URL(可留空)' ;; zh-TW) printf 'S3 Public URL(可留空)' ;; pt) printf 'URL pública do S3 (opcional)' ;; esac ;;
	backup_enabled) case "${lang}" in en) printf 'Enable automatic backups' ;; ja) printf '自動バックアップを有効にする' ;; ko) printf '자동 백업 활성화' ;; es) printf 'Habilitar copias de seguridad automáticas' ;; de) printf 'Automatische Backups aktivieren' ;; fr) printf 'Activer les sauvegardes automatiques' ;; zh-CN) printf '是否启用自动备份' ;; zh-TW) printf '是否啟用自動備份' ;; pt) printf 'Ativar backups automáticos' ;; esac ;;
	backup_schedule) case "${lang}" in en) printf 'Backup cron schedule' ;; ja) printf 'バックアップ cron' ;; ko) printf '백업 cron 일정' ;; es) printf 'Cron de respaldo' ;; de) printf 'Backup-Cronplan' ;; fr) printf 'Planification cron des sauvegardes' ;; zh-CN) printf '备份 cron' ;; zh-TW) printf '備份 cron' ;; pt) printf 'Cron de backup' ;; esac ;;
	backup_keep_local) case "${lang}" in en) printf 'Local backup retention count' ;; ja) printf 'ローカル保持数' ;; ko) printf '로컬 보관 개수' ;; es) printf 'Cantidad de copias locales a conservar' ;; de) printf 'Anzahl lokal aufzubewahrender Backups' ;; fr) printf 'Nombre de sauvegardes locales à conserver' ;; zh-CN) printf '本地保留份数' ;; zh-TW) printf '本地保留份數' ;; pt) printf 'Quantidade de backups locais a manter' ;; esac ;;
	backup_target) case "${lang}" in en) printf 'Remote backup target' ;; ja) printf 'リモートバックアップ先' ;; ko) printf '원격 백업 대상' ;; es) printf 'Destino remoto del backup' ;; de) printf 'Entferntes Backup-Ziel' ;; fr) printf 'Cible distante de sauvegarde' ;; zh-CN) printf '备份远端目标' ;; zh-TW) printf '備份遠端目標' ;; pt) printf 'Destino remoto do backup' ;; esac ;;
	backup_s3_endpoint) case "${lang}" in en) printf 'Backup S3 endpoint' ;; ja) printf 'バックアップ S3 エンドポイント' ;; ko) printf '백업 S3 엔드포인트' ;; es) printf 'Endpoint S3 para backup' ;; de) printf 'Backup-S3-Endpunkt' ;; fr) printf 'Endpoint S3 de sauvegarde' ;; zh-CN) printf '备份 S3 Endpoint' ;; zh-TW) printf '備份 S3 Endpoint' ;; pt) printf 'Endpoint S3 do backup' ;; esac ;;
	backup_s3_region) case "${lang}" in en) printf 'Backup S3 region' ;; ja) printf 'バックアップ S3 リージョン' ;; ko) printf '백업 S3 리전' ;; es) printf 'Región S3 para backup' ;; de) printf 'Backup-S3-Region' ;; fr) printf 'Région S3 de sauvegarde' ;; zh-CN) printf '备份 S3 Region' ;; zh-TW) printf '備份 S3 Region' ;; pt) printf 'Região S3 do backup' ;; esac ;;
	backup_s3_bucket) case "${lang}" in en) printf 'Backup S3 bucket' ;; ja) printf 'バックアップ S3 バケット' ;; ko) printf '백업 S3 버킷' ;; es) printf 'Bucket S3 para backup' ;; de) printf 'Backup-S3-Bucket' ;; fr) printf 'Bucket S3 de sauvegarde' ;; zh-CN) printf '备份 S3 Bucket' ;; zh-TW) printf '備份 S3 Bucket' ;; pt) printf 'Bucket S3 do backup' ;; esac ;;
	backup_s3_access_key) case "${lang}" in en) printf 'Backup S3 access key ID' ;; ja) printf 'バックアップ S3 Access Key ID' ;; ko) printf '백업 S3 Access Key ID' ;; es) printf 'Access Key ID S3 para backup' ;; de) printf 'Backup-S3 Access Key ID' ;; fr) printf 'Access Key ID S3 de sauvegarde' ;; zh-CN) printf '备份 S3 Access Key ID' ;; zh-TW) printf '備份 S3 Access Key ID' ;; pt) printf 'Access Key ID S3 do backup' ;; esac ;;
	backup_s3_secret_key) case "${lang}" in en) printf 'Backup S3 secret access key' ;; ja) printf 'バックアップ S3 Secret Access Key' ;; ko) printf '백업 S3 Secret Access Key' ;; es) printf 'Secret Access Key S3 para backup' ;; de) printf 'Backup-S3 Secret Access Key' ;; fr) printf 'Secret Access Key S3 de sauvegarde' ;; zh-CN) printf '备份 S3 Secret Access Key' ;; zh-TW) printf '備份 S3 Secret Access Key' ;; pt) printf 'Secret Access Key S3 do backup' ;; esac ;;
	backup_s3_prefix) case "${lang}" in en) printf 'Backup S3 prefix' ;; ja) printf 'バックアップ S3 プレフィックス' ;; ko) printf '백업 S3 프리픽스' ;; es) printf 'Prefijo S3 para backup' ;; de) printf 'Backup-S3-Präfix' ;; fr) printf 'Préfixe S3 de sauvegarde' ;; zh-CN) printf '备份 S3 Prefix' ;; zh-TW) printf '備份 S3 Prefix' ;; pt) printf 'Prefixo S3 do backup' ;; esac ;;
	optimization_enabled) case "${lang}" in en) printf 'Enable conservative tuning' ;; ja) printf '保守的チューニングを有効にする' ;; ko) printf '보수적 튜닝 활성화' ;; es) printf 'Habilitar ajuste conservador' ;; de) printf 'Konservative Optimierung aktivieren' ;; fr) printf 'Activer l’optimisation prudente' ;; zh-CN) printf '是否启用保守优化' ;; zh-TW) printf '是否啟用保守優化' ;; pt) printf 'Ativar ajuste conservador' ;; esac ;;
	wait_app_health) case "${lang}" in en) printf 'Waiting for the EmDash app health check' ;; ja) printf 'EmDash アプリのヘルスチェックを待機しています' ;; ko) printf 'EmDash 앱 상태 확인을 기다리는 중입니다' ;; es) printf 'Esperando la comprobación de salud de EmDash' ;; de) printf 'Warte auf den EmDash-Health-Check' ;; fr) printf 'Attente de la vérification de santé EmDash' ;; zh-CN) printf '等待 EmDash 应用健康检查通过' ;; zh-TW) printf '等待 EmDash 應用健康檢查通過' ;; pt) printf 'Aguardando a verificação de saúde do EmDash' ;; esac ;;
	app_health_warn) case "${lang}" in en) printf 'The local app health check did not pass in time.' ;; ja) printf 'アプリのローカルヘルスチェックが時間内に通りませんでした。' ;; ko) printf '앱 로컬 상태 확인이 제한 시간 내에 통과하지 못했습니다.' ;; es) printf 'La comprobación local de salud de la aplicación no pasó a tiempo.' ;; de) printf 'Der lokale App-Health-Check wurde nicht rechtzeitig erfolgreich abgeschlossen.' ;; fr) printf 'La vérification de santé locale de l’application n’a pas abouti à temps.' ;; zh-CN) printf '应用本地健康检查未在预期时间内通过。' ;; zh-TW) printf '應用本地健康檢查未在預期時間內通過。' ;; pt) printf 'A verificação local de saúde da aplicação não passou no tempo esperado.' ;; esac ;;
	wait_proxy_health) case "${lang}" in en) printf 'Waiting for the Caddy proxy health check' ;; ja) printf 'Caddy プロキシのヘルスチェックを待機しています' ;; ko) printf 'Caddy 프록시 상태 확인을 기다리는 중입니다' ;; es) printf 'Esperando la comprobación de salud del proxy Caddy' ;; de) printf 'Warte auf den Caddy-Proxy-Health-Check' ;; fr) printf 'Attente de la vérification de santé du proxy Caddy' ;; zh-CN) printf '等待 Caddy 代理健康检查通过' ;; zh-TW) printf '等待 Caddy 代理健康檢查通過' ;; pt) printf 'Aguardando a verificação de saúde do proxy Caddy' ;; esac ;;
	proxy_health_warn) case "${lang}" in en) printf 'The Caddy proxy health check did not pass in time.' ;; ja) printf 'Caddy プロキシのヘルスチェックが時間内に通りませんでした。' ;; ko) printf 'Caddy 프록시 상태 확인이 제한 시간 내에 통과하지 못했습니다.' ;; es) printf 'La comprobación de salud del proxy Caddy no pasó a tiempo.' ;; de) printf 'Der Caddy-Proxy-Health-Check wurde nicht rechtzeitig erfolgreich abgeschlossen.' ;; fr) printf 'La vérification de santé du proxy Caddy n’a pas abouti à temps.' ;; zh-CN) printf 'Caddy 代理健康检查未在预期时间内通过。' ;; zh-TW) printf 'Caddy 代理健康檢查未在預期時間內通過。' ;; pt) printf 'A verificação de saúde do proxy Caddy não passou no tempo esperado.' ;; esac ;;
	fetch_setup_status) case "${lang}" in en) printf 'Fetching setup status' ;; ja) printf 'セットアップ状態を取得しています' ;; ko) printf '설정 상태를 가져오는 중입니다' ;; es) printf 'Obteniendo el estado de configuración' ;; de) printf 'Setup-Status wird abgerufen' ;; fr) printf 'Récupération de l’état de configuration' ;; zh-CN) printf '获取 Setup 状态' ;; zh-TW) printf '取得 Setup 狀態' ;; pt) printf 'Obtendo o status da configuração' ;; esac ;;
	setup_status_done) case "${lang}" in en) printf 'Setup status: complete' ;; ja) printf 'セットアップ状態: 完了' ;; ko) printf '설정 상태: 완료' ;; es) printf 'Estado de configuración: completado' ;; de) printf 'Setup-Status: abgeschlossen' ;; fr) printf 'État de configuration : terminé' ;; zh-CN) printf 'Setup 状态: 已完成' ;; zh-TW) printf 'Setup 狀態：已完成' ;; pt) printf 'Status da configuração: concluído' ;; esac ;;
	setup_status_needs) case "${lang}" in en) printf 'Setup status: setup required, current step {step}, auth mode {auth_mode}' ;; ja) printf 'セットアップ状態: 初期化が必要です。現在のステップ {step}、認証モード {auth_mode}' ;; ko) printf '설정 상태: 초기 설정이 필요합니다. 현재 단계 {step}, 인증 모드 {auth_mode}' ;; es) printf 'Estado de configuración: se requiere configuración, paso actual {step}, modo de autenticación {auth_mode}' ;; de) printf 'Setup-Status: Einrichtung erforderlich, aktueller Schritt {step}, Auth-Modus {auth_mode}' ;; fr) printf 'État de configuration : configuration requise, étape actuelle {step}, mode d’authentification {auth_mode}' ;; zh-CN) printf 'Setup 状态: 需要初始化，当前步骤 {step}，认证模式 {auth_mode}' ;; zh-TW) printf 'Setup 狀態：需要初始化，目前步驟 {step}，認證模式 {auth_mode}' ;; pt) printf 'Status da configuração: configuração necessária, etapa atual {step}, modo de autenticação {auth_mode}' ;; esac ;;
	open_admin_guidance) case "${lang}" in en) printf 'Open the admin URL to complete the Setup Wizard.' ;; ja) printf '管理画面を開いて Setup Wizard を完了してください。' ;; ko) printf '관리자 URL을 열어 Setup Wizard를 완료하세요.' ;; es) printf 'Abre la URL de administración para completar el asistente de configuración.' ;; de) printf 'Öffne die Admin-URL, um den Setup Wizard abzuschließen.' ;; fr) printf 'Ouvrez l’URL d’administration pour terminer l’assistant de configuration.' ;; zh-CN) printf '请打开后台地址完成 Setup Wizard。' ;; zh-TW) printf '請打開後台位址完成 Setup Wizard。' ;; pt) printf 'Abra a URL de administração para concluir o assistente de configuração.' ;; esac ;;
	setup_status_parse_warn) case "${lang}" in en) printf 'Unable to parse setup-status.json' ;; ja) printf 'setup-status.json を解析できません' ;; ko) printf 'setup-status.json을 해석할 수 없습니다' ;; es) printf 'No se puede analizar setup-status.json' ;; de) printf 'setup-status.json konnte nicht geparst werden' ;; fr) printf 'Impossible d’analyser setup-status.json' ;; zh-CN) printf '无法解析 setup-status.json' ;; zh-TW) printf '無法解析 setup-status.json' ;; pt) printf 'Não foi possível analisar setup-status.json' ;; esac ;;
	write_only_skip) case "${lang}" in en) printf 'write-only mode skips runtime installation, object storage preflight, and Caddy installation.' ;; ja) printf 'write-only モードではランタイムのインストール、オブジェクトストレージ事前確認、Caddy インストールをスキップします。' ;; ko) printf 'write-only 모드에서는 런타임 설치, 객체 스토리지 사전 점검, Caddy 설치를 건너뜁니다.' ;; es) printf 'El modo write-only omite la instalación del runtime, la comprobación previa del almacenamiento de objetos y la instalación de Caddy.' ;; de) printf 'Im Modus write-only werden Runtime-Installation, Objektspeicher-Prüfung und Caddy-Installation übersprungen.' ;; fr) printf 'Le mode write-only ignore l’installation du runtime, la vérification du stockage objet et l’installation de Caddy.' ;; zh-CN) printf 'write-only 模式下将跳过运行时安装、对象存储上传测试和 Caddy 安装。' ;; zh-TW) printf 'write-only 模式下將跳過執行環境安裝、物件儲存預檢與 Caddy 安裝。' ;; pt) printf 'O modo write-only ignora a instalação do runtime, a verificação do armazenamento de objetos e a instalação do Caddy.' ;; esac ;;
	detect_public_ip) case "${lang}" in en) printf 'Detecting public IP addresses' ;; ja) printf 'パブリック IP を検出しています' ;; ko) printf '공인 IP를 감지하는 중입니다' ;; es) printf 'Detectando IP pública' ;; de) printf 'Öffentliche IP wird ermittelt' ;; fr) printf 'Détection des IP publiques' ;; zh-CN) printf '检测公网 IP' ;; zh-TW) printf '偵測公網 IP' ;; pt) printf 'Detectando IP público' ;; esac ;;
	activate_health_warn) case "${lang}" in en) printf 'Post-start health checks were not fully successful. Use emdashctl doctor for details.' ;; ja) printf '起動後のヘルスチェックが完全には通りませんでした。詳細は emdashctl doctor を使用してください。' ;; ko) printf '시작 후 상태 확인이 완전히 통과하지 못했습니다. 자세한 내용은 emdashctl doctor를 사용하세요.' ;; es) printf 'Las comprobaciones de salud posteriores al arranque no se completaron correctamente. Usa emdashctl doctor para más detalles.' ;; de) printf 'Die Health-Checks nach dem Start waren nicht vollständig erfolgreich. Verwende emdashctl doctor für Details.' ;; fr) printf 'Les vérifications de santé après démarrage ne se sont pas toutes déroulées correctement. Utilisez emdashctl doctor pour plus de détails.' ;; zh-CN) printf '启动后健康检查未完全通过，请使用 emdashctl doctor 进一步排查。' ;; zh-TW) printf '啟動後健康檢查未完全通過，請使用 emdashctl doctor 進一步排查。' ;; pt) printf 'As verificações de saúde após a inicialização não foram totalmente concluídas. Use emdashctl doctor para mais detalhes.' ;; esac ;;
	summary_generated_started) case "${lang}" in en) printf 'Configuration generated and compose stack started.' ;; ja) printf '設定を生成し、compose スタックを起動しました。' ;; ko) printf '구성이 생성되었고 compose 스택이 시작되었습니다.' ;; es) printf 'La configuración se generó y el stack de compose se inició.' ;; de) printf 'Konfiguration erstellt und Compose-Stack gestartet.' ;; fr) printf 'Configuration générée et stack compose démarré.' ;; zh-CN) printf '已生成配置并启动 compose。' ;; zh-TW) printf '已產生設定並啟動 compose。' ;; pt) printf 'Configuração gerada e stack compose iniciado.' ;; esac ;;
	summary_generated_only) case "${lang}" in en) printf 'Configuration generated. Services have not been started yet.' ;; ja) printf '設定を生成しました。サービスはまだ起動していません。' ;; ko) printf '구성이 생성되었습니다. 서비스는 아직 시작되지 않았습니다.' ;; es) printf 'Configuración generada. Los servicios aún no se han iniciado.' ;; de) printf 'Konfiguration erstellt. Die Dienste wurden noch nicht gestartet.' ;; fr) printf 'Configuration générée. Les services n’ont pas encore été démarrés.' ;; zh-CN) printf '已生成配置，服务尚未启动。' ;; zh-TW) printf '已產生設定，服務尚未啟動。' ;; pt) printf 'Configuração gerada. Os serviços ainda não foram iniciados.' ;; esac ;;
	summary_generated_write_only) case "${lang}" in en) printf 'Configuration generated. Compose stack not started.' ;; ja) printf '設定を生成しました。compose スタックは起動していません。' ;; ko) printf '구성이 생성되었습니다. compose 스택은 시작하지 않았습니다.' ;; es) printf 'Configuración generada. El stack de compose no se inició.' ;; de) printf 'Konfiguration erstellt. Compose-Stack wurde nicht gestartet.' ;; fr) printf 'Configuration générée. Le stack compose n’a pas été démarré.' ;; zh-CN) printf '已生成配置，未启动 compose。' ;; zh-TW) printf '已產生設定，尚未啟動 compose。' ;; pt) printf 'Configuração gerada. O stack compose não foi iniciado.' ;; esac ;;
	summary_start_services) case "${lang}" in en) printf 'To start services:' ;; ja) printf 'サービスを起動するには:' ;; ko) printf '서비스를 시작하려면:' ;; es) printf 'Para iniciar los servicios:' ;; de) printf 'Zum Starten der Dienste:' ;; fr) printf 'Pour démarrer les services :' ;; zh-CN) printf '如需启动服务:' ;; zh-TW) printf '如需啟動服務:' ;; pt) printf 'Para iniciar os serviços:' ;; esac ;;
	summary_config_files) case "${lang}" in en) printf 'Config files:' ;; ja) printf '設定ファイル:' ;; ko) printf '구성 파일:' ;; es) printf 'Archivos de configuración:' ;; de) printf 'Konfigurationsdateien:' ;; fr) printf 'Fichiers de configuration :' ;; zh-CN) printf '配置文件:' ;; zh-TW) printf '設定檔:' ;; pt) printf 'Arquivos de configuração:' ;; esac ;;
	summary_project_paths) case "${lang}" in en) printf 'Project paths:' ;; ja) printf 'プロジェクトパス:' ;; ko) printf '프로젝트 경로:' ;; es) printf 'Rutas del proyecto:' ;; de) printf 'Projektpfade:' ;; fr) printf 'Chemins du projet :' ;; zh-CN) printf '项目目录:' ;; zh-TW) printf '專案路徑:' ;; pt) printf 'Caminhos do projeto:' ;; esac ;;
	summary_control_commands) case "${lang}" in en) printf 'Control commands:' ;; ja) printf '運用コマンド:' ;; ko) printf '관리 명령:' ;; es) printf 'Comandos de control:' ;; de) printf 'Steuerbefehle:' ;; fr) printf 'Commandes de contrôle :' ;; zh-CN) printf '控制命令:' ;; zh-TW) printf '控制命令:' ;; pt) printf 'Comandos de controle:' ;; esac ;;
	summary_access_urls) case "${lang}" in en) printf 'Access URLs:' ;; ja) printf 'アクセス URL:' ;; ko) printf '접속 URL:' ;; es) printf 'URLs de acceso:' ;; de) printf 'Zugriffs-URLs:' ;; fr) printf 'URLs d’accès :' ;; zh-CN) printf '访问地址:' ;; zh-TW) printf '存取位址:' ;; pt) printf 'URLs de acesso:' ;; esac ;;
	summary_site) case "${lang}" in en) printf 'Site' ;; ja) printf 'サイト' ;; ko) printf '사이트' ;; es) printf 'Sitio' ;; de) printf 'Website' ;; fr) printf 'Site' ;; zh-CN) printf '站点' ;; zh-TW) printf '網站' ;; pt) printf 'Site' ;; esac ;;
	summary_admin) case "${lang}" in en) printf 'Admin' ;; ja) printf '管理画面' ;; ko) printf '관리자' ;; es) printf 'Admin' ;; de) printf 'Admin' ;; fr) printf 'Admin' ;; zh-CN) printf '后台' ;; zh-TW) printf '後台' ;; pt) printf 'Admin' ;; esac ;;
	first_run_installed) case "${lang}" in en) printf 'EmDash has been installed.' ;; ja) printf 'EmDash のインストールが完了しました。' ;; ko) printf 'EmDash 설치가 완료되었습니다.' ;; es) printf 'EmDash se ha instalado.' ;; de) printf 'EmDash wurde installiert.' ;; fr) printf 'EmDash a été installé.' ;; zh-CN) printf 'EmDash 已安装。' ;; zh-TW) printf 'EmDash 已安裝。' ;; pt) printf 'O EmDash foi instalado.' ;; esac ;;
	first_run_site_address) case "${lang}" in en) printf 'Site URL:' ;; ja) printf 'サイト URL:' ;; ko) printf '사이트 URL:' ;; es) printf 'URL del sitio:' ;; de) printf 'Website-URL:' ;; fr) printf 'URL du site :' ;; zh-CN) printf '站点地址:' ;; zh-TW) printf '網站位址:' ;; pt) printf 'URL do site:' ;; esac ;;
	first_run_admin_address) case "${lang}" in en) printf 'Admin URL:' ;; ja) printf '管理画面 URL:' ;; ko) printf '관리자 URL:' ;; es) printf 'URL de administración:' ;; de) printf 'Admin-URL:' ;; fr) printf 'URL d’administration :' ;; zh-CN) printf '后台地址:' ;; zh-TW) printf '後台位址:' ;; pt) printf 'URL de administração:' ;; esac ;;
	first_run_health_check) case "${lang}" in en) printf 'Health check:' ;; ja) printf 'ヘルスチェック:' ;; ko) printf '상태 확인:' ;; es) printf 'Comprobación de salud:' ;; de) printf 'Health-Check:' ;; fr) printf 'Vérification de santé :' ;; zh-CN) printf '健康检查:' ;; zh-TW) printf '健康檢查:' ;; pt) printf 'Verificação de saúde:' ;; esac ;;
	first_run_first_visit) case "${lang}" in en) printf 'First visit:' ;; ja) printf '初回アクセス:' ;; ko) printf '첫 방문:' ;; es) printf 'Primer acceso:' ;; de) printf 'Erster Aufruf:' ;; fr) printf 'Première visite :' ;; zh-CN) printf '首次访问说明:' ;; zh-TW) printf '首次造訪說明:' ;; pt) printf 'Primeiro acesso:' ;; esac ;;
	first_run_step1) case "${lang}" in en) printf '1. Open the admin URL' ;; ja) printf '1. 管理画面 URL を開く' ;; ko) printf '1. 관리자 URL 열기' ;; es) printf '1. Abre la URL de administración' ;; de) printf '1. Öffne die Admin-URL' ;; fr) printf '1. Ouvrez l’URL d’administration' ;; zh-CN) printf '1. 打开后台地址' ;; zh-TW) printf '1. 打開後台位址' ;; pt) printf '1. Abra a URL de administração' ;; esac ;;
	first_run_step2) case "${lang}" in en) printf '2. Complete the Setup Wizard' ;; ja) printf '2. Setup Wizard を完了する' ;; ko) printf '2. Setup Wizard 완료' ;; es) printf '2. Completa el asistente de configuración' ;; de) printf '2. Schließe den Setup Wizard ab' ;; fr) printf '2. Terminez l’assistant de configuration' ;; zh-CN) printf '2. 完成 Setup Wizard' ;; zh-TW) printf '2. 完成 Setup Wizard' ;; pt) printf '2. Conclua o assistente de configuração' ;; esac ;;
	first_run_step3) case "${lang}" in en) printf '3. Create the first admin account and passkey' ;; ja) printf '3. 最初の管理者アカウントと Passkey を作成する' ;; ko) printf '3. 첫 관리자 계정과 패스키를 생성' ;; es) printf '3. Crea la primera cuenta de administrador y passkey' ;; de) printf '3. Erstelle das erste Admin-Konto und den Passkey' ;; fr) printf '3. Créez le premier compte administrateur et la passkey' ;; zh-CN) printf '3. 创建第一个管理员账号和 Passkey' ;; zh-TW) printf '3. 建立第一個管理員帳號與 Passkey' ;; pt) printf '3. Crie a primeira conta de administrador e a passkey' ;; esac ;;
	first_run_ops_commands) case "${lang}" in en) printf 'Operations commands:' ;; ja) printf '運用コマンド:' ;; ko) printf '운영 명령:' ;; es) printf 'Comandos operativos:' ;; de) printf 'Betriebsbefehle:' ;; fr) printf 'Commandes d’exploitation :' ;; zh-CN) printf '运维命令:' ;; zh-TW) printf '維運命令:' ;; pt) printf 'Comandos operacionais:' ;; esac ;;
	*)
		printf '%s' "${key}"
		;;
	esac
}

print_usage() {
	local lang="${EMDASH_INSTALL_LANG:-en}"
	case "${lang}" in
	en)
		cat <<'EOF'
EmDash installer

Usage:
  bash install.sh [--lang <code>] [--non-interactive] [--write-only] [--activate]

Options:
  --non-interactive  Use only environment variables and defaults
  --write-only       Generate config and project files only, do not start compose
  --activate         Generate files and immediately build / up
  -h, --help         Show help

Common environment variables:
  EMDASH_INSTALL_TEMPLATE
  EMDASH_INSTALL_ROOT_DIR
  EMDASH_INSTALL_DOMAIN
  EMDASH_INSTALL_ADMIN_EMAIL
  EMDASH_INSTALL_DB_DRIVER
  EMDASH_INSTALL_SESSION_DRIVER
  EMDASH_INSTALL_STORAGE_DRIVER
  EMDASH_INSTALL_USE_CADDY
  EMDASH_INSTALL_ENABLE_HTTPS
  EMDASH_INSTALL_APP_IMAGE
  EMDASH_INSTALL_APP_BASE_IMAGE
  EMDASH_INSTALL_PG_PASSWORD
  EMDASH_INSTALL_REDIS_PASSWORD
EOF
		;;
	ja)
		cat <<'EOF'
EmDash installer

使い方:
  bash install.sh [--lang <code>] [--non-interactive] [--write-only] [--activate]

オプション:
  --non-interactive  環境変数と既定値のみを使用し、質問しません
  --write-only       設定とプロジェクトファイルのみ生成し、compose は起動しません
  --activate         生成後すぐに build / up を実行します
  -h, --help         ヘルプを表示

主な環境変数:
  EMDASH_INSTALL_TEMPLATE
  EMDASH_INSTALL_ROOT_DIR
  EMDASH_INSTALL_DOMAIN
  EMDASH_INSTALL_ADMIN_EMAIL
  EMDASH_INSTALL_DB_DRIVER
  EMDASH_INSTALL_SESSION_DRIVER
  EMDASH_INSTALL_STORAGE_DRIVER
  EMDASH_INSTALL_USE_CADDY
  EMDASH_INSTALL_ENABLE_HTTPS
  EMDASH_INSTALL_APP_IMAGE
  EMDASH_INSTALL_APP_BASE_IMAGE
  EMDASH_INSTALL_PG_PASSWORD
  EMDASH_INSTALL_REDIS_PASSWORD
EOF
		;;
	ko)
		cat <<'EOF'
EmDash installer

사용법:
  bash install.sh [--lang <code>] [--non-interactive] [--write-only] [--activate]

옵션:
  --non-interactive  환경 변수와 기본값만 사용하고 질문하지 않습니다
  --write-only       설정과 프로젝트 파일만 생성하고 compose는 시작하지 않습니다
  --activate         생성 후 즉시 build / up 을 실행합니다
  -h, --help         도움말 표시

주요 환경 변수:
  EMDASH_INSTALL_TEMPLATE
  EMDASH_INSTALL_ROOT_DIR
  EMDASH_INSTALL_DOMAIN
  EMDASH_INSTALL_ADMIN_EMAIL
  EMDASH_INSTALL_DB_DRIVER
  EMDASH_INSTALL_SESSION_DRIVER
  EMDASH_INSTALL_STORAGE_DRIVER
  EMDASH_INSTALL_USE_CADDY
  EMDASH_INSTALL_ENABLE_HTTPS
  EMDASH_INSTALL_APP_IMAGE
  EMDASH_INSTALL_APP_BASE_IMAGE
  EMDASH_INSTALL_PG_PASSWORD
  EMDASH_INSTALL_REDIS_PASSWORD
EOF
		;;
	es)
		cat <<'EOF'
EmDash installer

Uso:
  bash install.sh [--lang <code>] [--non-interactive] [--write-only] [--activate]

Opciones:
  --non-interactive  Usa solo variables de entorno y valores predeterminados
  --write-only       Genera solo la configuración y los archivos del proyecto, sin iniciar compose
  --activate         Genera y ejecuta build / up inmediatamente
  -h, --help         Muestra la ayuda

Variables de entorno comunes:
  EMDASH_INSTALL_TEMPLATE
  EMDASH_INSTALL_ROOT_DIR
  EMDASH_INSTALL_DOMAIN
  EMDASH_INSTALL_ADMIN_EMAIL
  EMDASH_INSTALL_DB_DRIVER
  EMDASH_INSTALL_SESSION_DRIVER
  EMDASH_INSTALL_STORAGE_DRIVER
  EMDASH_INSTALL_USE_CADDY
  EMDASH_INSTALL_ENABLE_HTTPS
  EMDASH_INSTALL_APP_IMAGE
  EMDASH_INSTALL_APP_BASE_IMAGE
  EMDASH_INSTALL_PG_PASSWORD
  EMDASH_INSTALL_REDIS_PASSWORD
EOF
		;;
	de)
		cat <<'EOF'
EmDash installer

Verwendung:
  bash install.sh [--lang <code>] [--non-interactive] [--write-only] [--activate]

Optionen:
  --non-interactive  Nur Umgebungsvariablen und Standardwerte verwenden
  --write-only       Nur Konfiguration und Projektdateien erzeugen, compose nicht starten
  --activate         Dateien erzeugen und sofort build / up ausführen
  -h, --help         Hilfe anzeigen

Häufige Umgebungsvariablen:
  EMDASH_INSTALL_TEMPLATE
  EMDASH_INSTALL_ROOT_DIR
  EMDASH_INSTALL_DOMAIN
  EMDASH_INSTALL_ADMIN_EMAIL
  EMDASH_INSTALL_DB_DRIVER
  EMDASH_INSTALL_SESSION_DRIVER
  EMDASH_INSTALL_STORAGE_DRIVER
  EMDASH_INSTALL_USE_CADDY
  EMDASH_INSTALL_ENABLE_HTTPS
  EMDASH_INSTALL_APP_IMAGE
  EMDASH_INSTALL_APP_BASE_IMAGE
  EMDASH_INSTALL_PG_PASSWORD
  EMDASH_INSTALL_REDIS_PASSWORD
EOF
		;;
	fr)
		cat <<'EOF'
EmDash installer

Utilisation :
  bash install.sh [--lang <code>] [--non-interactive] [--write-only] [--activate]

Options :
  --non-interactive  Utiliser uniquement les variables d’environnement et les valeurs par défaut
  --write-only       Générer seulement la configuration et les fichiers du projet, sans démarrer compose
  --activate         Générer puis lancer immédiatement build / up
  -h, --help         Afficher l’aide

Variables d’environnement courantes :
  EMDASH_INSTALL_TEMPLATE
  EMDASH_INSTALL_ROOT_DIR
  EMDASH_INSTALL_DOMAIN
  EMDASH_INSTALL_ADMIN_EMAIL
  EMDASH_INSTALL_DB_DRIVER
  EMDASH_INSTALL_SESSION_DRIVER
  EMDASH_INSTALL_STORAGE_DRIVER
  EMDASH_INSTALL_USE_CADDY
  EMDASH_INSTALL_ENABLE_HTTPS
  EMDASH_INSTALL_APP_IMAGE
  EMDASH_INSTALL_APP_BASE_IMAGE
  EMDASH_INSTALL_PG_PASSWORD
  EMDASH_INSTALL_REDIS_PASSWORD
EOF
		;;
	zh-CN)
		cat <<'EOF'
EmDash 安装器

用法:
  bash install.sh [--lang <code>] [--non-interactive] [--write-only] [--activate]

参数:
  --non-interactive  仅使用环境变量和默认值，不提问
  --write-only       只生成配置和项目文件，不启动 compose
  --activate         生成后立即 build / up
  -h, --help         显示帮助

常用环境变量:
  EMDASH_INSTALL_TEMPLATE
  EMDASH_INSTALL_ROOT_DIR
  EMDASH_INSTALL_DOMAIN
  EMDASH_INSTALL_ADMIN_EMAIL
  EMDASH_INSTALL_DB_DRIVER
  EMDASH_INSTALL_SESSION_DRIVER
  EMDASH_INSTALL_STORAGE_DRIVER
  EMDASH_INSTALL_USE_CADDY
  EMDASH_INSTALL_ENABLE_HTTPS
  EMDASH_INSTALL_APP_IMAGE
  EMDASH_INSTALL_APP_BASE_IMAGE
  EMDASH_INSTALL_PG_PASSWORD
  EMDASH_INSTALL_REDIS_PASSWORD
EOF
		;;
	zh-TW)
		cat <<'EOF'
EmDash 安裝器

用法:
  bash install.sh [--lang <code>] [--non-interactive] [--write-only] [--activate]

參數:
  --non-interactive  僅使用環境變數與預設值，不提問
  --write-only       只產生設定與專案檔案，不啟動 compose
  --activate         產生後立即 build / up
  -h, --help         顯示說明

常用環境變數:
  EMDASH_INSTALL_TEMPLATE
  EMDASH_INSTALL_ROOT_DIR
  EMDASH_INSTALL_DOMAIN
  EMDASH_INSTALL_ADMIN_EMAIL
  EMDASH_INSTALL_DB_DRIVER
  EMDASH_INSTALL_SESSION_DRIVER
  EMDASH_INSTALL_STORAGE_DRIVER
  EMDASH_INSTALL_USE_CADDY
  EMDASH_INSTALL_ENABLE_HTTPS
  EMDASH_INSTALL_APP_IMAGE
  EMDASH_INSTALL_APP_BASE_IMAGE
  EMDASH_INSTALL_PG_PASSWORD
  EMDASH_INSTALL_REDIS_PASSWORD
EOF
		;;
	pt)
		cat <<'EOF'
EmDash installer

Uso:
  bash install.sh [--lang <code>] [--non-interactive] [--write-only] [--activate]

Opções:
  --non-interactive  Usa apenas variáveis de ambiente e valores padrão
  --write-only       Gera apenas a configuração e os arquivos do projeto, sem iniciar o compose
  --activate         Gera e executa build / up imediatamente
  -h, --help         Mostra a ajuda

Variáveis de ambiente comuns:
  EMDASH_INSTALL_TEMPLATE
  EMDASH_INSTALL_ROOT_DIR
  EMDASH_INSTALL_DOMAIN
  EMDASH_INSTALL_ADMIN_EMAIL
  EMDASH_INSTALL_DB_DRIVER
  EMDASH_INSTALL_SESSION_DRIVER
  EMDASH_INSTALL_STORAGE_DRIVER
  EMDASH_INSTALL_USE_CADDY
  EMDASH_INSTALL_ENABLE_HTTPS
  EMDASH_INSTALL_APP_IMAGE
  EMDASH_INSTALL_APP_BASE_IMAGE
  EMDASH_INSTALL_PG_PASSWORD
  EMDASH_INSTALL_REDIS_PASSWORD
EOF
		;;
	esac
}
