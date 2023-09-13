function submit_post() {
    let formElements = window.document.getElementById('submitform').elements;

    let title = formElements['title'].value;
    let content = formElements['content'].value;

    fetch("/post", {
        method: "POST",
        body: JSON.stringify({
            name: title,
            content: content,
        }),
        headers: {
            "Content-type": "application/json; charset=UTF-8"
        }
    }).then(function() { window.location.reload(false); });
}