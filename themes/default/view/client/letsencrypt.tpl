<script>
    // Requesting a certificate takes tens of seconds, during which a domain sits in a 'to...'
    // status waiting for the backend. While any row is in that state, poll letsencrypt_status.php
    // and patch the affected cells, so that the customer need not reload the page to learn the
    // outcome. The status text and icon are decided by PHP, this only puts them in place.
    (function () {
        var POLL_URL = "letsencrypt_status.php";
        var FAST_INTERVAL = 3000;   // most requests finish within the first minute
        var SLOW_INTERVAL = 10000;
        var FAST_PERIOD = 60000;    // back off to SLOW_INTERVAL beyond this point
        var DEADLINE = 300000;      // give up; the row goes on showing that it is still pending

        var startedAt = Date.now();

        function elapsed() {
            return Date.now() - startedAt;
        }

        function schedule() {
            window.setTimeout(poll, elapsed() < FAST_PERIOD ? FAST_INTERVAL : SLOW_INTERVAL);
        }

        function applyRow(data) {
            var row = document.querySelector(
                'tr[data-le-type="' + data.type + '"][data-le-id="' + data.id + '"]'
            );
            if (!row) {
                return;
            }

            var status = row.querySelector("[data-le-status]");
            if (status) {
                status.className = "icon i_" + data.icon;
                status.textContent = data.status;
            }

            var note = row.querySelector("[data-le-note]");
            if (note) {
                note.textContent = data.note;
            }

            var forward = row.querySelector("[data-le-forward]");
            if (forward) {
                forward.textContent = data.httpForward;
            }

            if (data.pending) {
                row.setAttribute("data-le-pending", "");
            } else {
                row.removeAttribute("data-le-pending");
            }
        }

        function poll() {
            fetch(POLL_URL, {
                credentials: "same-origin",
                headers: {
                    // is_xhr() looks for this header, which fetch, unlike jQuery, does not send
                    "X-Requested-With": "XMLHttpRequest",
                    "Accept": "application/json"
                }
            }).then(function (response) {
                if (response.status === 403) {
                    // The session expired while the page was left open
                    window.location.replace("/index.php");
                    return null;
                }
                if (!response.ok) {
                    throw new Error("Unexpected response status " + response.status);
                }
                return response.json();
            }).then(function (data) {
                if (!data) {
                    return;
                }
                data.rows.forEach(applyRow);
                if (data.pending && elapsed() < DEADLINE) {
                    schedule();
                }
            }).catch(function () {
                // A failed poll is not worth reporting: the rows still read as pending, which they
                // are, and the next poll may well succeed
                if (elapsed() < DEADLINE) {
                    schedule();
                }
            });
        }

        document.addEventListener("DOMContentLoaded", function () {
            if (document.querySelector("tr[data-le-pending]")) {
                schedule();
            }
        });
    })();
</script>

<h3 class="domains"><span>{TR_DOMAINS}</span></h3>

<!-- BDP: domain_list -->
<table class="firstColFixed">
    <thead>
    <tr>
        <th>{TR_STATUS}</th>
        <th>{TR_DOMAIN_NAME}</th>
        <th>{TR_HTTP_FORWARD}</th>
        <th>{TR_NOTE}</th>
        <th>{TR_ACTION}</th>
    </tr>
    </thead>
    <tbody>
    <!-- BDP: domain_item -->
    <tr data-le-type="domain" data-le-id="{ID}"{PENDING}>
        <td><div class="icon i_{STATUS_ICON}" data-le-status>{STATUS}</div></td>
        <td><label for="keyid_{ID}">{DOMAIN_NAME}</label></td>
        <td data-le-forward>{HTTP_FORWARD}</td>
        <td data-le-note>{NOTE}</td>
        <td>
            <a class="icon i_edit" href="{EDIT_LINK}" title="{EDIT}">{EDIT}</a>
        </td></tr>
    <!-- EDP: domain_item -->
    </tbody>
</table>
<!-- EDP: domains_list -->

<!-- BDP: domain_aliases_block -->
<h3 class="domains"><span>{TR_DOMAIN_ALIASES}</span></h3>
<!-- BDP: als_message -->
<div class="static_info">{ALS_MSG}</div>
<!-- EDP: als_message -->
<!-- BDP: als_list -->
<table class="firstColFixed datatable">
    <thead>
    <tr>
        <th>{TR_STATUS}</th>
        <th>{TR_DOMAIN_NAME}</th>
        <th>{TR_HTTP_FORWARD}</th>
        <th>{TR_NOTE}</th>
        <th>{TR_ACTION}</th>
    </tr>
    </thead>
    <tbody>
    <!-- BDP: als_item -->
    <tr data-le-type="alias" data-le-id="{ID}"{PENDING}>
        <td><div class="icon i_{STATUS_ICON}" data-le-status>{STATUS}</div></td>
        <td><label for="keyid_{ID}">{DOMAIN_NAME}</label></td>
        <td data-le-forward>{HTTP_FORWARD}</td>
        <td data-le-note>{NOTE}</td>
        <td>
            <a class="icon i_edit" href="{EDIT_LINK}" title="{EDIT}">{EDIT}</a>
        </td></tr>
    <!-- EDP: als_item -->
    </tbody>
</table>
<!-- EDP: als_list -->
<!-- EDP: domain_aliases_block -->

<!-- BDP: subdomains_block -->
<h3 class="domains"><span>{TR_SUBDOMAINS}</span></h3>
<!-- BDP: sub_message -->
<div class="static_info">{SUB_MSG}</div>
<!-- EDP: sub_message -->
<!-- BDP: sub_list -->
<table class="firstColFixed datatable">
    <thead>
    <tr>
        <th>{TR_STATUS}</th>
        <th>{TR_DOMAIN_NAME}</th>
        <th>{TR_HTTP_FORWARD}</th>
        <th>{TR_NOTE}</th>
        <th>{TR_ACTION}</th>
    </tr>
    </thead>
    <tbody>
    <!-- BDP: sub_item -->
    <tr data-le-type="subdomain" data-le-id="{ID}"{PENDING}>
        <td><div class="icon i_{STATUS_ICON}" data-le-status>{STATUS}</div></td>
        <td><label for="keyid_{ID}">{DOMAIN_NAME}</label></td>
        <td data-le-forward>{HTTP_FORWARD}</td>
        <td data-le-note>{NOTE}</td>
        <td>
            <a class="icon i_edit" href="{EDIT_LINK}" title="{EDIT}">{EDIT}</a>
        </td></tr>
    <!-- EDP: sub_item -->
    </tbody>
</table>
<!-- EDP: sub_list -->
<!-- EDP: subdomains_block -->
