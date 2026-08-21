const TARGET_DIR = String.raw`D:\zotero`;


function getInvocationItems() {
    if (
        typeof items !== "undefined"
        && Array.isArray(items)
        && items.length
    ) {
        return items;
    }

    if (typeof item !== "undefined" && item) {
        return [item];
    }

    return [];
}


function leafName(path) {
    return path.split(/[\\/]/).pop();
}


function fileExtension(filename) {
    const dotIndex = filename.lastIndexOf(".");

    if (
        dotIndex <= 0
        || dotIndex === filename.length - 1
    ) {
        return "no-extension";
    }

    return filename
        .slice(dotIndex + 1)
        .toLowerCase();
}


function pathToFile(path) {
    const file = Components.classes[
        "@mozilla.org/file/local;1"
    ].createInstance(Components.interfaces.nsIFile);

    file.initWithPath(path);

    return file;
}


function ensureDirectory(path) {
    const directory = pathToFile(path);

    if (!directory.exists()) {
        directory.create(
            Components.interfaces.nsIFile.DIRECTORY_TYPE,
            0o755
        );
    }

    if (!directory.isDirectory()) {
        throw new Error(
            `目标路径不是文件夹：${path}`
        );
    }

    return directory;
}


function getExtensionDirectory(root, extension) {
    const directory = root.clone();
    directory.append(extension);

    if (!directory.exists()) {
        directory.create(
            Components.interfaces.nsIFile.DIRECTORY_TYPE,
            0o755
        );
    }

    if (!directory.isDirectory()) {
        throw new Error(
            `附件分类路径不是文件夹：${directory.path}`
        );
    }

    return directory;
}


function getUniqueName(directory, filename) {
    let candidate = directory.clone();
    candidate.append(filename);

    if (!candidate.exists()) {
        return filename;
    }

    const dotIndex = filename.lastIndexOf(".");
    const hasExtension =
        dotIndex > 0
        && dotIndex < filename.length - 1;

    const basename = hasExtension
        ? filename.slice(0, dotIndex)
        : filename;

    const extension = hasExtension
        ? filename.slice(dotIndex)
        : "";

    let index = 1;

    while (true) {
        const uniqueName =
            `${basename} (${index})${extension}`;

        candidate = directory.clone();
        candidate.append(uniqueName);

        if (!candidate.exists()) {
            return uniqueName;
        }

        index++;
    }
}


async function getLocalFile(attachment) {
    if (
        !attachment
        || !attachment.isAttachment()
        || attachment.attachmentLinkMode
            === Zotero.Attachments.LINK_MODE_LINKED_URL
    ) {
        return null;
    }

    const path =
        await attachment.getFilePathAsync();

    if (!path) {
        return null;
    }

    const file = pathToFile(path);

    if (!file.exists() || !file.isFile()) {
        return null;
    }

    return {
        path,
        name: leafName(path),
    };
}


async function collectAttachments(selectedItems) {
    const attachmentMap = new Map();

    async function addAttachment(attachment) {
        if (
            !attachment
            || attachmentMap.has(attachment.id)
        ) {
            return;
        }

        const file =
            await getLocalFile(attachment);

        if (file) {
            attachmentMap.set(
                attachment.id,
                file
            );
        }
    }

    for (const selected of selectedItems) {
        if (selected.isAttachment()) {
            await addAttachment(selected);
            continue;
        }

        if (!selected.isRegularItem()) {
            continue;
        }

        for (const attachmentID of selected.getAttachments()) {
            await addAttachment(
                await Zotero.Items.getAsync(attachmentID)
            );
        }
    }

    return Array.from(
        attachmentMap.values()
    );
}


function copyAttachment(file, root) {
    const source = pathToFile(file.path);
    const extension = fileExtension(file.name);
    const directory =
        getExtensionDirectory(
            root,
            extension
        );

    const destinationName =
        getUniqueName(
            directory,
            file.name
        );

    source.copyToFollowingLinks(
        directory,
        destinationName
    );
}


function errorMessage(error) {
    return (
        error && error.message
            ? error.message
            : String(error)
    );
}


// ============================================================
// Zotero 原生 ProgressWindow 通知
// ============================================================

function showProgressWindow(
    headline,
    descriptions,
    closeDelay = 3500
) {
    const progress =
        new Zotero.ProgressWindow({
            closeOnClick: true,
        });

    progress.changeHeadline(headline);

    for (const description of descriptions) {
        progress.addDescription(description);
    }

    progress.show();
    progress.startCloseTimer(closeDelay);

    return progress;
}


function showSummary(summary) {
    const hasFailure =
        summary.failed > 0;

    const headline = hasFailure
        ? "附件导出完成 · 存在失败"
        : "附件导出完成";

    const descriptions = [
        `附件 ${summary.total}｜成功 ${summary.copied}｜失败 ${summary.failed}`,
        `目标目录：${TARGET_DIR}`,
        ...summary.details,
    ];

    showProgressWindow(
        headline,
        descriptions,
        hasFailure ? 8000 : 3500
    );

    return [
        "附件导出完成",
        `附件总数：${summary.total}`,
        `成功：${summary.copied}`,
        `失败：${summary.failed}`,
        `目标目录：${TARGET_DIR}`,
        ...summary.details,
    ].join("\n");
}


// ============================================================
// 主程序
// ============================================================

(async () => {
    // Actions & Tags 批处理时使用 items。
    // 如果同时进入逐条 item 调用，则直接跳过，避免重复处理。
    if (
        typeof item !== "undefined"
        && item
    ) {
        return;
    }

    const selectedItems =
        getInvocationItems();

    if (!selectedItems.length) {
        throw new Error(
            "请先选中文献或其文件附件"
        );
    }

    const attachments =
        await collectAttachments(selectedItems);

    if (!attachments.length) {
        throw new Error(
            "选中条目中没有找到可复制的本地附件"
        );
    }

    const root =
        ensureDirectory(TARGET_DIR);

    const summary = {
        total: attachments.length,
        copied: 0,
        failed: 0,
        details: [],
    };

    for (const file of attachments) {
        try {
            copyAttachment(
                file,
                root
            );

            summary.copied++;
        }
        catch (error) {
            summary.failed++;
            summary.details.push(
                `错误：${errorMessage(error)}｜附件：${file.name}`
            );
        }
    }

    return showSummary(summary);
})().catch(error => {
    const message =
        errorMessage(error);

    showProgressWindow(
        "附件导出失败",
        [
            `错误：${message}`,
        ],
        8000
    );

    Zotero.logError(error);
});
