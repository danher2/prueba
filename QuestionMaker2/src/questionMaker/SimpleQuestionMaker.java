package questionMaker;

import java.util.Scanner;

public class SimpleQuestionMaker {

	public static void main(String[] args) {
		// TODO Auto-generated method stub

		Answers answer = new Answers();

		// Using Scanner for Getting Input from User
		Scanner in = new Scanner(System.in);
		boolean endWhy = false;
		String lastAnswer = "";
		String lastQuestion = "";
		String whyanswer;
		String whyHowAnswer;
		int count = 2;
		int exit = 0;

		System.out.println("");
		System.out.println("");
		System.out.println("OK, lets get started with this");
		System.out.println("Instrutions:");
		System.out.println("type 1 to keep asking in the current w or type 2 to skip to the next w");

		// what
		System.out.println("");
		System.out.println("");
		System.out.println("What happen?");
		answer.setWhatAnswer(in.nextLine());
		while (!(answer.getWhatAnswer().equals("2"))) {
			lastAnswer = answer.getWhatAnswer();
			System.out.println("");
			System.out.println("what " + count + ":");
			System.out.print("Q= ");
			answer.setWhatQuestion(in.nextLine());
			lastQuestion = answer.getWhatQuestion();
			System.out.print("R= ");
			answer.setWhatAnswer(in.nextLine());
			lastAnswer = answer.getWhatAnswer();
			count++;
			// to skip or keep the w
			answer.setWhatAnswer(in.nextLine());

		}
		
		//why
		count = 2;
		System.out.println("");
		System.out.println("");
		System.out.println("Why did it happen?");
		answer.setWhyAnswer(in.nextLine());
		while (!(answer.getWhyAnswer().equals("2"))) {
			lastAnswer = answer.getWhyAnswer();
			System.out.println("");
			System.out.println("why " + count + ":");
			System.out.print("Q= ");
			answer.setWhyQuestion(in.nextLine());
			lastQuestion = answer.getWhyQuestion();
			System.out.print("R= ");
			answer.setWhyAnswer(in.nextLine());
			lastAnswer = answer.getWhyAnswer();
			count++;
			// to skip or keep the w
			answer.setWhyAnswer(in.nextLine());

		}
		
		
		//how
		count = 2;
		System.out.println("");
		System.out.println("");
		System.out.println("How did it happen?");
		answer.setHowAnswer(in.nextLine());
		while (!(answer.getHowAnswer().equals("2"))) {
			lastAnswer = answer.getHowAnswer();
			System.out.println("");
			System.out.println("how " + count + ":");
			System.out.print("Q= ");
			answer.setHowQuestion(in.nextLine());
			lastQuestion = answer.getHowQuestion();
			System.out.print("R= ");
			answer.setHowAnswer(in.nextLine());
			lastAnswer = answer.getHowAnswer();
			count++;
			// to skip or keep the w
			answer.setHowAnswer(in.nextLine());
		
		}
		//who
		count = 2;
		System.out.println("");
		System.out.println("");
		System.out.println("who is involved?");
		answer.setWhoAnswer(in.nextLine());
		while (!(answer.getWhoAnswer().equals("2"))) {
			lastAnswer = answer.getWhoAnswer();
			System.out.println("");
			System.out.println("who " + count + ":");
			System.out.print("Q= ");
			answer.setWhoQuestion(in.nextLine());
			lastQuestion = answer.getWhoQuestion();
			System.out.print("R= ");
			answer.setWhoAnswer(in.nextLine());
			lastAnswer = answer.getWhoAnswer();
			count++;
			// to skip or keep the w
			answer.setWhoAnswer(in.nextLine());
		
		}
		
		//where
		count = 2;
		System.out.println("");
		System.out.println("");
		System.out.println("where did it happen?");
		answer.setWhereAnswer(in.nextLine());
		while (!(answer.getWhereAnswer().equals("2"))) {
			lastAnswer = answer.getWhereAnswer();
			System.out.println("");
			System.out.println("where " + count + ":");
			System.out.print("Q= ");
			answer.setWhereQuestion(in.nextLine());
			lastQuestion = answer.getWhereQuestion();
			System.out.print("R= ");
			answer.setWhereAnswer(in.nextLine());
			lastAnswer = answer.getWhereAnswer();
			count++;
			// to skip or keep the w
			answer.setWhereAnswer(in.nextLine());
		
		}
		
		//when
		count = 2;
		System.out.println("");
		System.out.println("");
		System.out.println("when did it happen?");
		answer.setWhenAnswer(in.nextLine());
		while (!(answer.getWhenAnswer().equals("2"))) {
			lastAnswer = answer.getWhenAnswer();
			System.out.println("");
			System.out.println("when " + count + ":");
			System.out.print("Q= ");
			answer.setWhenQuestion(in.nextLine());
			lastQuestion = answer.getWhenQuestion();
			System.out.print("R= ");
			answer.setWhenAnswer(in.nextLine());
			lastAnswer = answer.getWhenAnswer();
			count++;
			// to skip or keep the w
			answer.setWhenAnswer(in.nextLine());
		
		}
	}
}