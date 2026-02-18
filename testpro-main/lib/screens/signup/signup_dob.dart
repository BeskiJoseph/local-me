import 'package:flutter/material.dart';
import '../../widgets/primary_button.dart';
import '../../models/signup_data.dart';
import 'signup_profile.dart';

class SignupDobScreen extends StatefulWidget {
  final SignupData data;
  const SignupDobScreen({super.key, required this.data});

  @override
  State<SignupDobScreen> createState() => _SignupDobScreenState();
}

class _SignupDobScreenState extends State<SignupDobScreen> {
  DateTime? selectedDate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Date of Birth")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 📅 DOB Field
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      selectedDate == null
                          ? "Select your date of birth"
                          : "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}",
                      style: TextStyle(
                        color: selectedDate == null
                            ? Colors.grey
                            : Colors.black,
                      ),
                    ),
                    const Icon(Icons.calendar_today, size: 18),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // ➡️ Next Button
            PrimaryButton(
  text: "Next",
  enabled: selectedDate != null,
  onTap: () {
    widget.data.dob =
        "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}";

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SignupProfileScreen(data: widget.data),
      ),
    );
  },
),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      initialDate: DateTime(2000),
    );

    if (date != null) {
      setState(() {
        selectedDate = date;
      });
    }
  }
}
