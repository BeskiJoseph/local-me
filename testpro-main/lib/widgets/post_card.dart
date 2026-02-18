import 'package:flutter/material.dart';
import '../models/post.dart';
import '../screens/event_post_card.dart';
import 'post/post_header.dart';
import 'post/post_media_display.dart';
import 'post/post_action_row.dart';

class PostCard extends StatelessWidget {
  final Post post;

  const PostCard({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    if (post.isEvent) {
      return EventPostCard(post: post);
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0x1A000000),
            offset: const Offset(0, 6),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Header (Avatar, Name, Time, More)
            PostHeader(post: post),

            // Post Content Text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                post.body,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF2C2C2E),
                  height: 1.5,
                  fontFamily: 'Inter',
                ),
              ),
            ),

            // Media Display (Image/Video)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: PostMediaDisplay(post: post),
            ),

            const SizedBox(height: 16),

            // Action Row (Like, Comment, Replies)
            PostActionRow(post: post),
            
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}