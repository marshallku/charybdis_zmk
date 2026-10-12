/*
 * Split peripheral advertising watchdog.
 *
 * ZMK v0.3 peripheral.c restarts advertising from its disconnected() callback.
 * Zephyr 3.5 still holds the connection object at that point (the `recycled`
 * callback that ZMK main uses does not exist yet), so with CONFIG_BT_MAX_CONN=1
 * bt_le_adv_start() can fail with -ENOMEM. advertising_cb() only LOG_ERRs and
 * nothing retries, so the half advertises to nobody until it is reset.
 *
 * This retries directed advertising to the bonded central for as long as the
 * peripheral is disconnected. When ZMK's own attempt worked, the start returns
 * -EALREADY and nothing changes.
 */

#include <zephyr/kernel.h>
#include <zephyr/init.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/logging/log.h>

#include <zmk/split/bluetooth/peripheral.h>

LOG_MODULE_REGISTER(charybdis_adv_watchdog, CONFIG_ZMK_LOG_LEVEL);

#define RETRY_INTERVAL K_MSEC(CONFIG_CHARYBDIS_ADV_WATCHDOG_INTERVAL_MS)
// Leave ZMK's own boot-time advertising (after settings load) alone.
#define BOOT_DELAY K_SECONDS(10)

static void find_bond(const struct bt_bond_info *info, void *user_data) {
    bt_addr_le_t *addr = user_data;

    if (bt_addr_le_cmp(addr, BT_ADDR_LE_NONE) == 0) {
        bt_addr_le_copy(addr, &info->addr);
    }
}

static void watchdog_cb(struct k_work *work);
static K_WORK_DELAYABLE_DEFINE(watchdog_work, watchdog_cb);

static void watchdog_cb(struct k_work *work) {
    if (zmk_split_bt_peripheral_is_connected()) {
        return;
    }

    bt_addr_le_t central = *BT_ADDR_LE_NONE;
    bt_foreach_bond(BT_ID_DEFAULT, find_bond, &central);

    // Unbonded means first-time pairing, which ZMK handles with undirected advertising.
    if (bt_addr_le_cmp(&central, BT_ADDR_LE_NONE) == 0) {
        return;
    }

    // High duty first, same as ZMK. On timeout ZMK's connected() falls back to low duty.
    const int err = bt_le_adv_start(BT_LE_ADV_CONN_DIR(&central), NULL, 0, NULL, 0);
    if (err == 0) {
        LOG_WRN("Advertising was stopped while disconnected, restarted it");
    } else if (err != -EALREADY) {
        LOG_DBG("Advertising restart failed (%d), retrying", err);
    }

    k_work_reschedule(&watchdog_work, RETRY_INTERVAL);
}

static void connected(struct bt_conn *conn, uint8_t err) {
    if (err == 0) {
        k_work_cancel_delayable(&watchdog_work);
        return;
    }
    k_work_reschedule(&watchdog_work, RETRY_INTERVAL);
}

static void disconnected(struct bt_conn *conn, uint8_t reason) {
    k_work_reschedule(&watchdog_work, RETRY_INTERVAL);
}

BT_CONN_CB_DEFINE(adv_watchdog_conn_cb) = {
    .connected = connected,
    .disconnected = disconnected,
};

static int adv_watchdog_init(void) {
    k_work_schedule(&watchdog_work, BOOT_DELAY);
    return 0;
}

SYS_INIT(adv_watchdog_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);
