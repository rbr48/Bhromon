/// Translations for the tour group screens. Read through
/// `context.l10n.translate(key, args: {...})`. Every key must exist in both
/// languages; a test enforces that.
class TourTranslationKeys {
  static const Map<String, Map<String, String>> localizedValues = {
    'en': {
      // ── Shared actions ─────────────────────────────────────────────────────
      'tour_cancel': 'Cancel',
      'tour_save': 'Save',
      'tour_send': 'Send',
      'tour_post': 'Post',
      'tour_details': 'Details',
      'tour_default_destination': 'Tour',

      // ── Notice board & meeting point ───────────────────────────────────────
      'tour_notice_board_title': 'Notice board & meeting point',
      'tour_notice_board': 'Notice board',
      'tour_meeting_point_default':
          '{destination} main meeting point (hotel lobby)',
      'tour_hotel_lobby': 'Hotel lobby',
      'tour_live_meeting_point': 'Live meeting point',
      'tour_edit_meeting_point': 'Change meeting point',
      'tour_place_name': 'Place name',
      'tour_map_link_label': 'Map link (https://)',
      'tour_map_link_needs_https': 'The map link must start with https://.',
      'tour_meeting_point_save_failed':
          'Could not save the meeting point: {error}',
      'tour_view_on_map': 'View on map',
      'tour_notice_new': 'New notice',
      'tour_notice_new_title': 'Post a new notice',
      'tour_notice_edit_title': 'Edit notice',
      'tour_notice_heading': 'Heading',
      'tour_notice_urgent': 'Urgent notice',
      'tour_notice_post_admin_only':
          'Could not post the notice. Only admins can post notices.',
      'tour_notice_update_admin_only':
          'Could not change the notice. Only admins can change it.',
      'tour_notice_delete_failed': 'Could not delete the notice.',
      'tour_delete_notice': 'Delete notice',
      'tour_notices_load_failed': 'Could not load notices.',
      'tour_no_notices': 'No notices yet.',
      'tour_notice_sender': 'From {author} • {date}',

      // ── Discussion channels ────────────────────────────────────────────────
      'tour_channels_title': 'Group channels',
      'tour_channel_general': '# general chat',
      'tour_channel_food': '# food & restaurants',
      'tour_channel_places': '# sightseeing & spots',
      'tour_channel_safety': '# emergencies & safety',
      'tour_message_hint': 'Write a message...',
      'tour_message_send_failed':
          'Could not send the message. Your text is kept: {error}',
      'tour_messages_load_failed': 'Could not load messages.',
      'tour_no_messages': 'No messages yet. Say hello to everyone!',

      // ── Bus seats ──────────────────────────────────────────────────────────
      'tour_bus_seats_title': 'Bus seat allocator',
      'tour_seat_change_failed': 'Could not change the seat: {error}',
      'tour_seats_unavailable':
          'Seat details are not visible. Check that you are a member of this tour.',
      'tour_seat_free': 'Free',
      'tour_seat_booked': 'Booked',
      'tour_seats_booked_count': 'Booked: {booked} / {total}',
      'tour_door': 'Door',
      'tour_driver': 'Driver',
      'tour_seat_label': 'Seat {number}',
      'tour_free_seat': 'Free this seat',
      'tour_pick_passenger': 'Choose a passenger:',
      'tour_on_this_seat': 'On this seat',
      'tour_seat_release_warning': 'Choosing another seat frees this one.',

      // ── Logistics hub ──────────────────────────────────────────────────────
      'tour_logistics_title': 'Logistics (seats and rooms)',
      'tour_tab_bus': 'Bus seats',
      'tour_tab_hotel': 'Hotel rooms',
    },
    'bn': {
      // ── Shared actions ─────────────────────────────────────────────────────
      'tour_cancel': 'বাতিল',
      'tour_save': 'সংরক্ষণ',
      'tour_send': 'পাঠান',
      'tour_post': 'পোস্ট করুন',
      'tour_details': 'বিস্তারিত',
      'tour_default_destination': 'ট্যুর',

      // ── Notice board & meeting point ───────────────────────────────────────
      'tour_notice_board_title': 'নোটিশ বোর্ড ও মিটিং পয়েন্ট',
      'tour_notice_board': 'নোটিশ বোর্ড',
      'tour_meeting_point_default':
          '{destination} প্রধান মিটিং পয়েন্ট (হোটেল লবি)',
      'tour_hotel_lobby': 'হোটেল লবি',
      'tour_live_meeting_point': 'লাইভ মিটিং পয়েন্ট',
      'tour_edit_meeting_point': 'মিটিং পয়েন্ট বদলান',
      'tour_place_name': 'স্থানের নাম',
      'tour_map_link_label': 'ম্যাপের লিংক (https://)',
      'tour_map_link_needs_https': 'ম্যাপের লিংক https:// দিয়ে শুরু হতে হবে।',
      'tour_meeting_point_save_failed':
          'মিটিং পয়েন্ট সংরক্ষণ করা যায়নি: {error}',
      'tour_view_on_map': 'ম্যাপে দেখুন',
      'tour_notice_new': 'নতুন নোটিশ',
      'tour_notice_new_title': 'নতুন নোটিশ জারি করুন',
      'tour_notice_edit_title': 'নোটিশ সম্পাদনা',
      'tour_notice_heading': 'শিরোনাম',
      'tour_notice_urgent': 'জরুরি নোটিশ',
      'tour_notice_post_admin_only':
          'নোটিশ পাঠানো যায়নি: শুধু অ্যাডমিন নোটিশ দিতে পারেন।',
      'tour_notice_update_admin_only':
          'নোটিশ বদলানো যায়নি: শুধু অ্যাডমিন বদলাতে পারেন।',
      'tour_notice_delete_failed': 'নোটিশ মোছা যায়নি।',
      'tour_delete_notice': 'নোটিশ মুছুন',
      'tour_notices_load_failed': 'নোটিশ লোড করা যায়নি।',
      'tour_no_notices': 'এখনও কোনো নোটিশ নেই।',
      'tour_notice_sender': 'প্রেরক: {author} • {date}',

      // ── Discussion channels ────────────────────────────────────────────────
      'tour_channels_title': 'আলোচনা চ্যানেল',
      'tour_channel_general': '# সাধারণ আড্ডা',
      'tour_channel_food': '# খাবার ও রেস্তোরাঁ',
      'tour_channel_places': '# ঘোরাঘুরি ও স্পট',
      'tour_channel_safety': '# জরুরি ও নিরাপত্তা',
      'tour_message_hint': 'বার্তা লিখুন...',
      'tour_message_send_failed': 'বার্তা পাঠানো যায়নি। লেখাটি রইল: {error}',
      'tour_messages_load_failed': 'বার্তা লোড করা যায়নি।',
      'tour_no_messages': 'এখনও কোনো বার্তা নেই। সবাইকে হ্যালো বলুন!',

      // ── Bus seats ──────────────────────────────────────────────────────────
      'tour_bus_seats_title': 'বাসের সিট',
      'tour_seat_change_failed': 'সিট বদলানো যায়নি: {error}',
      'tour_seats_unavailable':
          'সিটের তথ্য দেখা যাচ্ছে না। আপনি এই ট্যুরের সদস্য কি না দেখুন।',
      'tour_seat_free': 'খালি',
      'tour_seat_booked': 'বুকড',
      'tour_seats_booked_count': 'বুকড: {booked} / {total}',
      'tour_door': 'দরজা',
      'tour_driver': 'ড্রাইভার',
      'tour_seat_label': 'সিট {number}',
      'tour_free_seat': 'সিট খালি করুন',
      'tour_pick_passenger': 'যাত্রী বাছাই করুন:',
      'tour_on_this_seat': 'এই সিটে',
      'tour_seat_release_warning':
          'অন্য সিট বাছাই করলে এখানকার সিট ছেড়ে দেওয়া হবে',

      // ── Logistics hub ──────────────────────────────────────────────────────
      'tour_logistics_title': 'লজিস্টিকস (সিট ও রুম বণ্টন)',
      'tour_tab_bus': 'বাসের সিট',
      'tour_tab_hotel': 'হোটেল রুম',
    },
  };
}
