// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

package struct DiskExclusionStrings {
    package let listTitle: String
    package let addButton: String
    package let otherDrive: String
    package let removeButton: String
    package let customPlaceholder: String
    package let caption: String
}

extension FeatureStrings {
    package static func diskExclusions(_ language: AppLanguage) -> DiskExclusionStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension DiskExclusionStrings {
    package static let enUS = DiskExclusionStrings(
        listTitle: "Excluded drives",
        addButton: "Add drive…",
        otherDrive: "Other drive name…",
        removeButton: "Remove",
        customPlaceholder: "Drive or volume name",
        caption: "Drives in this list are never unmounted when using Eject all disks."
    )

    package static let ptBR = DiskExclusionStrings(
        listTitle: "Discos excluídos",
        addButton: "Adicionar disco…",
        otherDrive: "Outro nome de disco…",
        removeButton: "Remover",
        customPlaceholder: "Nome do disco ou volume",
        caption: "Os discos nesta lista nunca são desmontados ao ejetar todos os discos."
    )

    package static let tr = DiskExclusionStrings(
        listTitle: "Hariç tutulan sürücüler",
        addButton: "Sürücü ekle…",
        otherDrive: "Diğer sürücü adı…",
        removeButton: "Kaldır",
        customPlaceholder: "Sürücü veya birim adı",
        caption: "Bu listedeki sürücüler Tüm diskleri çıkar kullanılırken hiçbir zaman çıkarılmaz."
    )

    package static let ru = DiskExclusionStrings(
        listTitle: "Исключённые диски",
        addButton: "Добавить диск…",
        otherDrive: "Другое имя диска…",
        removeButton: "Удалить",
        customPlaceholder: "Имя диска или тома",
        caption: "Диски из этого списка никогда не извлекаются при действии «Извлечь все диски»."
    )

    package static let es = DiskExclusionStrings(
        listTitle: "Discos excluidos",
        addButton: "Añadir disco…",
        otherDrive: "Otro nombre de disco…",
        removeButton: "Quitar",
        customPlaceholder: "Nombre del disco o volumen",
        caption: "Los discos de esta lista nunca se expulsan al expulsar todos los discos."
    )

    package static let sk = DiskExclusionStrings(
        listTitle: "Vylúčené disky",
        addButton: "Pridať disk…",
        otherDrive: "Iný názov disku…",
        removeButton: "Odstrániť",
        customPlaceholder: "Názov disku alebo zväzku",
        caption: "Disky v tomto zozname sa nikdy neodpoja pri použití Vysunúť všetky disky."
    )

    package static let de = DiskExclusionStrings(
        listTitle: "Ausgenommene Laufwerke",
        addButton: "Laufwerk hinzufügen…",
        otherDrive: "Anderer Laufwerksname…",
        removeButton: "Entfernen",
        customPlaceholder: "Laufwerks- oder Volumename",
        caption: "Laufwerke in dieser Liste werden beim Auswerfen aller Festplatten niemals ausgeworfen."
    )

    package static let fr = DiskExclusionStrings(
        listTitle: "Disques exclus",
        addButton: "Ajouter un disque…",
        otherDrive: "Autre nom de disque…",
        removeButton: "Retirer",
        customPlaceholder: "Nom du disque ou volume",
        caption: "Les disques de cette liste ne sont jamais éjectés lors de l’éjection de tous les disques."
    )

    package static let it = DiskExclusionStrings(
        listTitle: "Dischi esclusi",
        addButton: "Aggiungi disco…",
        otherDrive: "Altro nome del disco…",
        removeButton: "Rimuovi",
        customPlaceholder: "Nome del disco o volume",
        caption: "I dischi in questo elenco non vengono mai espulsi quando si espellono tutti i dischi."
    )

    package static let ja = DiskExclusionStrings(
        listTitle: "除外するドライブ",
        addButton: "ドライブを追加…",
        otherDrive: "その他のドライブ名…",
        removeButton: "削除",
        customPlaceholder: "ドライブまたはボリューム名",
        caption: "このリストにあるドライブは「すべてのディスクを取り出す」を実行しても取り出されません。"
    )

    package static let ko = DiskExclusionStrings(
        listTitle: "제외된 드라이브",
        addButton: "드라이브 추가…",
        otherDrive: "다른 드라이브 이름…",
        removeButton: "제거",
        customPlaceholder: "드라이브 또는 볼륨 이름",
        caption: "이 목록에 있는 드라이브는 모든 디스크 추출 시 추출되지 않습니다."
    )

    package static let zhHans = DiskExclusionStrings(
        listTitle: "排除的驱动器",
        addButton: "添加驱动器…",
        otherDrive: "其他驱动器名称…",
        removeButton: "移除",
        customPlaceholder: "驱动器或宗卷名称",
        caption: "使用“推出所有磁盘”时，此列表中的驱动器绝不会被推出。"
    )

    package static let zhTW = DiskExclusionStrings(
        listTitle: "排除的磁碟機",
        addButton: "加入磁碟機…",
        otherDrive: "其他磁碟機名稱…",
        removeButton: "移除",
        customPlaceholder: "磁碟機或卷宗名稱",
        caption: "使用「退出所有磁碟」時，此列表中的磁碟機絕不會被退出。"
    )

    package static let zhHK = DiskExclusionStrings(
        listTitle: "排除的磁碟機",
        addButton: "加入磁碟機…",
        otherDrive: "其他磁碟機名稱…",
        removeButton: "移除",
        customPlaceholder: "磁碟機或宗卷名稱",
        caption: "使用「推出所有磁碟」時，此清單中的磁碟機絕不會被推出。"
    )
    package static let uk = DiskExclusionStrings(
        listTitle: "Виключені диски",
        addButton: "Додати диск…",
        otherDrive: "Інша назва диска…",
        removeButton: "Видалити",
        customPlaceholder: "Назва диска або тому",
        caption: "Диски з цього списку ніколи не демонтуються при використанні «Вийняти всі диски»."
    )
}
