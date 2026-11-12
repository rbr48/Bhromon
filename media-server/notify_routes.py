"""Notification dispatch and platform-admin maintenance routes for the Bhromon media server.

Reads `authenticate`, `require_member`, `require_platform_admin`, `check_tour_id`,
`notification_engine`, `notification_watcher`, `chat_db`, and `chat_is_encrypted`
from `main` at request time so test fixtures that patch `main.*` continue to work.
"""

from typing import Any, Dict, Optional

from fastapi import APIRouter, Header, HTTPException, status
from fastapi.concurrency import run_in_threadpool

notify_router = APIRouter()


@notify_router.get("/notify/status")
async def notification_status(authorization: Optional[str] = Header(None)):
    import main

    caller = await run_in_threadpool(main.authenticate, authorization)
    await run_in_threadpool(main.require_platform_admin, caller)
    return {
        "watcher_running": main.notification_watcher._is_running,
        "listeners": len(main.notification_watcher.active_listeners),
        "stats": main.notification_engine.stats,
    }


@notify_router.post("/notify/sos")
async def trigger_sos_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    """Pushes the caller's own safety alert now. The alert must be in the tour, theirs, open and recent
    (notifications.push_own_sos). Nothing is pushed for an alert that is not, and the sender's name is
    the group's name for them, not one sent here."""
    import main

    caller = await run_in_threadpool(main.authenticate, authorization)
    tour_id = str(payload.get("tourId", ""))
    alert_id = str(payload.get("alertId", ""))
    main.check_tour_id(tour_id)
    if not alert_id or len(alert_id) > 128 or "/" in alert_id:
        raise HTTPException(status_code=400, detail="That alert id is not valid.")
    await run_in_threadpool(main.require_member, tour_id, caller)

    res = await run_in_threadpool(
        main.notification_engine.push_own_sos,
        tour_id,
        alert_id,
        caller.email,
    )
    if res.get("status") == "refused":
        raise HTTPException(status_code=403, detail="That alert cannot be pushed.")
    return res


@notify_router.post("/notify/channel")
async def trigger_channel_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    import main

    caller = await run_in_threadpool(main.authenticate, authorization)
    tour_id = payload.get("tourId", "")
    channel_id = payload.get("channelId", "")
    message_id = payload.get("messageId", "")
    sender_name = payload.get("senderName", "A member")
    text = payload.get("text", "")
    mentions = payload.get("mentions", [])
    attachments = payload.get("attachments", [])
    kind = payload.get("kind", "text")
    main.check_tour_id(tour_id)
    await run_in_threadpool(main.require_member, tour_id, caller)

    res = await run_in_threadpool(
        main.notification_engine.send_channel_message_notification,
        tour_id=tour_id,
        channel_id=channel_id,
        message_id=message_id,
        sender_email=caller.email,
        sender_name=sender_name,
        text=text,
        mentions=mentions,
        attachments=attachments,
        kind=kind,
    )
    return res


@notify_router.post("/notify/chat")
async def trigger_chat_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    import main

    caller = await run_in_threadpool(main.authenticate, authorization)
    chat_id = payload.get("chatId", "")
    sender_id = payload.get("senderId", "")
    text = payload.get("text", "")
    message_type = payload.get("type", "text")

    # Only a member of the conversation can notify it, and only as themselves.
    participants = await run_in_threadpool(main.chat_db.participants_of, chat_id)
    if (
        participants is None
        or caller.uid not in participants
        or sender_id != caller.uid
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only notify a chat you are in, as yourself.",
        )

    # The text of an encrypted chat never reaches the server, so none is pushed.
    encrypted = await main.chat_is_encrypted(chat_id)
    if encrypted:
        text = ""
        message_type = "text"

    res = await run_in_threadpool(
        main.notification_engine.send_chat_notification,
        chat_id=chat_id,
        sender_id=sender_id,
        text=text,
        message_type=message_type,
        encrypted=encrypted,
    )
    return res


@notify_router.post("/notify/post")
async def trigger_post_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    import main

    caller = await run_in_threadpool(main.authenticate, authorization)
    tour_id = payload.get("tourId", "")
    post_id = payload.get("postId", "")
    author_name = payload.get("authorName", "A member")
    caption = payload.get("caption", "")
    is_reel = bool(payload.get("isReel", False))
    image_url = payload.get("imageUrl")
    main.check_tour_id(tour_id)
    await run_in_threadpool(main.require_member, tour_id, caller)

    res = await run_in_threadpool(
        main.notification_engine.send_post_notification,
        tour_id=tour_id,
        post_id=post_id,
        author_email=caller.email,
        author_name=author_name,
        caption=caption,
        is_reel=is_reel,
        image_url=image_url,
    )
    return res


@notify_router.post("/notify/comment")
async def trigger_comment_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    import main

    caller = await run_in_threadpool(main.authenticate, authorization)
    tour_id = payload.get("tourId", "")
    post_id = payload.get("postId", "")
    comment_id = payload.get("commentId", "")
    commenter_name = payload.get("commenterName", "A member")
    text = payload.get("text", "")
    post_author_email = payload.get("postAuthorEmail")
    main.check_tour_id(tour_id)
    await run_in_threadpool(main.require_member, tour_id, caller)

    res = await run_in_threadpool(
        main.notification_engine.send_comment_notification,
        tour_id=tour_id,
        post_id=post_id,
        comment_id=comment_id,
        commenter_email=caller.email,
        commenter_name=commenter_name,
        text=text,
        post_author_email=post_author_email,
    )
    return res


@notify_router.post("/notify/reaction")
async def trigger_reaction_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    import main

    caller = await run_in_threadpool(main.authenticate, authorization)
    tour_id = payload.get("tourId", "")
    post_id = payload.get("postId", "")
    reactor_name = payload.get("reactorName", "A member")
    reaction = payload.get("reaction", "like")
    post_author_email = payload.get("postAuthorEmail")
    main.check_tour_id(tour_id)
    await run_in_threadpool(main.require_member, tour_id, caller)

    res = await run_in_threadpool(
        main.notification_engine.send_reaction_notification,
        tour_id=tour_id,
        post_id=post_id,
        reactor_email=caller.email,
        reactor_name=reactor_name,
        reaction=reaction,
        post_author_email=post_author_email,
    )
    return res


@notify_router.post("/notify/notice")
async def trigger_notice_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    import main

    caller = await run_in_threadpool(main.authenticate, authorization)
    tour_id = payload.get("tourId", "")
    notice_id = payload.get("noticeId", "")
    title = payload.get("title", "")
    body = payload.get("body", "")
    priority = payload.get("priority", "normal")
    main.check_tour_id(tour_id)
    await run_in_threadpool(main.require_member, tour_id, caller)

    res = await run_in_threadpool(
        main.notification_engine.send_notice_notification,
        tour_id=tour_id,
        notice_id=notice_id,
        author_email=caller.email,
        title=title,
        body=body,
        priority=priority,
    )
    return res


@notify_router.post("/notify/ledger")
async def trigger_ledger_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    import main

    caller = await run_in_threadpool(main.authenticate, authorization)
    tour_id = payload.get("tourId", "")
    expense_id = payload.get("expenseId", "")
    payer_name = payload.get("payerName", "A member")
    title = payload.get("title", "trip expense")
    amount_paisa = int(payload.get("amountPaisa", 0))
    main.check_tour_id(tour_id)
    await run_in_threadpool(main.require_member, tour_id, caller)

    res = await run_in_threadpool(
        main.notification_engine.send_ledger_notification,
        tour_id=tour_id,
        expense_id=expense_id,
        added_by_email=caller.email,
        payer_name=payer_name,
        title=title,
        amount_paisa=amount_paisa,
    )
    return res


@notify_router.post("/admin/broadcast")
async def trigger_broadcast_notification(
    payload: Dict[str, Any],
    authorization: Optional[str] = Header(None),
):
    import main

    caller = await run_in_threadpool(main.authenticate, authorization)
    await run_in_threadpool(main.require_platform_admin, caller)
    title = payload.get("title", "")
    body = payload.get("body", "")
    data = payload.get("data")
    image_url = payload.get("imageUrl")
    if not title or not body:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Title and body are required.",
        )

    res = await run_in_threadpool(
        main.notification_engine.send_broadcast_notification,
        title=title,
        body=body,
        data=data,
        image_url=image_url,
    )
    return res


@notify_router.post("/admin/maintenance")
async def trigger_maintenance(
    authorization: Optional[str] = Header(None),
):
    import main

    caller = await run_in_threadpool(main.authenticate, authorization)
    await run_in_threadpool(main.require_platform_admin, caller)
    res = await run_in_threadpool(main.notification_engine.run_retention_sweep)
    return res
