import 'package:flutter/material.dart';
import '../../models/signup_data.dart';
import '../../widgets/input_field.dart';

import '../../widgets/primary_button.dart';
import 'signup_dob.dart';


class SignupPersonalScreen extends StatelessWidget {
  final SignupData data;
  SignupPersonalScreen({super.key, required this.data});

  final firstController = TextEditingController();
  final lastController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Your name")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            InputField(hint: "First name", controller: firstController),
            const SizedBox(height: 12),
            InputField(hint: "Last name", controller: lastController),
            const Spacer(),
            PrimaryButton(
              text: "Next",
              onTap: () {
                data.firstName = firstController.text;
                data.lastName = lastController.text;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SignupDobScreen(data: data),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
