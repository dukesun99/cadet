defmodule Cadet.CourseTest do
  use Cadet.DataCase

  alias Cadet.Repo
  alias Cadet.Course
  alias Cadet.Course.Group
  alias Cadet.Course.Material
  alias Cadet.Course.Upload

  describe "Announcements" do
    test "create valid" do
      poster = insert(:user)

      assert {:ok, announcement} =
               Course.create_announcement(poster, %{
                 title: "Test",
                 content: "Some content"
               })

      assert announcement.title == "Test"
      assert announcement.content == "Some content"
    end

    test "create invalid" do
      poster = insert(:user)

      assert {:error, changeset} =
               Course.create_announcement(poster, %{
                 title: "",
                 content: "Some content"
               })

      assert errors_on(changeset) == %{title: ["can't be blank"]}
    end

    test "edit valid" do
      announcement = insert(:announcement)

      assert {:ok, announcement} =
               Course.edit_announcement(announcement.id, %{title: "New title", pinned: true})

      assert announcement.title == "New title"
      assert announcement.pinned
    end

    test "get valid" do
      announcement = insert(:announcement)
      assert announcement == Course.get_announcement(announcement.id)
    end

    test "edit invalid" do
      announcement = insert(:announcement)
      assert {:error, changeset} = Course.edit_announcement(announcement.id, %{title: ""})
      assert errors_on(changeset) == %{title: ["can't be blank"]}
    end

    test "edit not found" do
      assert {:error, :not_found} = Course.edit_announcement(255, %{})
    end

    test "delete valid" do
      announcement = insert(:announcement)
      assert {:ok, _} = Course.delete_announcement(announcement.id)
    end

    test "delete not found" do
      assert {:error, :not_found} = Course.delete_announcement(255)
    end
  end

  describe "Points" do
    test "give manual xp valid" do
      staff = insert(:user, %{role: :staff})
      student = insert(:user)

      result =
        Course.give_manual_xp(staff, student, %{
          reason: "DG XP Week 4",
          amount: 100
        })

      assert {:ok, point} = result
      assert point.amount == 100
    end

    test "give manual xp invalid" do
      staff = insert(:user, %{role: :staff})
      student = insert(:user)

      result =
        Course.give_manual_xp(staff, student, %{
          reason: "DG XP Week 4",
          amount: -100
        })

      assert {:error, changeset} = result
      assert errors_on(changeset) == %{amount: ["must be greater than 0"]}
    end

    test "give manual xp not staff" do
      student = insert(:user)

      result =
        Course.give_manual_xp(student, student, %{
          reason: "DG XP Week 4",
          amount: 100
        })

      assert {:error, :insufficient_privileges} = result
    end

    test "delete manual xp" do
      point = insert(:point)
      student = insert(:user)
      staff = insert(:user, %{role: :staff})
      admin = insert(:user, %{role: :admin})
      assert {:error, :not_found} = Course.delete_manual_xp(student, 200)
      assert {:error, :insufficient_privileges} = Course.delete_manual_xp(staff, point.id)
      assert {:error, :insufficient_privileges} = Course.delete_manual_xp(student, point.id)
      assert {:ok, _} = Course.delete_manual_xp(point.given_by, point.id)
      point = insert(:point)
      assert {:ok, _} = Course.delete_manual_xp(admin, point.id)
    end
  end

  describe "Groups" do
    test "valid assign group" do
      staff = insert(:user, %{role: :staff})
      student = insert(:user, %{role: :student})
      another_staff = insert(:user, %{role: :staff})

      assert {:ok, assignment} = Course.assign_group(staff, student)
      assert assignment.leader_id == staff.id
      assert assignment.student_id == student.id

      assert {:ok, assignment} = Course.assign_group(another_staff, student)
      assert assignment.leader_id == another_staff.id
      assert assignment.student_id == student.id

      assert Repo.get_by(Group, leader_id: staff.id) == nil
    end

    test "invalid leader or student" do
      student = insert(:user, %{role: :student})
      another_student = insert(:user, %{role: :student})
      staff = insert(:user, %{role: :staff})
      another_staff = insert(:user, %{role: :staff})

      assert {:error, :invalid} == Course.assign_group(student, another_student)
      assert {:error, :invalid} == Course.assign_group(staff, staff)
      assert {:error, :invalid} == Course.assign_group(staff, another_staff)
    end

    test "list group members" do
      staff = insert(:user, %{role: :staff})
      insert(:group, %{leader: staff})
      insert(:group, %{leader: staff})

      result = Course.list_students_by_leader(staff)
      assert Enum.count(result) == 2
    end
  end

  describe "Material" do
    setup do
      on_exit(fn -> File.rm_rf!("uploads/test/materials") end)
    end

    test "create root folder valid" do
      uploader = insert(:user, %{role: :staff})

      result =
        Course.create_material_folder(uploader, %{
          name: "Lecture Notes",
          description: "This is where the notes"
        })

      assert {:ok, material} = result
      assert material.uploader == uploader
      assert material.name == "Lecture Notes"
      assert material.description == "This is where the notes"
    end

    test "create folder with parent valid" do
      parent = insert(:material_folder)
      uploader = insert(:user, %{role: :staff})

      result =
        Course.create_material_folder(parent, uploader, %{
          name: "Lecture Notes"
        })

      assert {:ok, material} = result
      assert material.parent_id == parent.id
    end

    test "create folder invalid" do
      uploader = insert(:user, %{role: :staff})

      assert {:error, changeset} =
               Course.create_material_folder(uploader, %{
                 name: ""
               })

      assert errors_on(changeset) == %{
               name: ["can't be blank"]
             }
    end

    test "upload file to folder then delete it" do
      uploader = insert(:user, %{role: :staff})
      folder = insert(:material_folder)

      upload = %Plug.Upload{
        content_type: "text/plain",
        filename: "upload.txt",
        path: "test/fixtures/upload.txt"
      }

      result =
        Course.upload_material_file(folder, uploader, %{
          name: "Test Upload",
          file: upload
        })

      assert {:ok, material} = result
      path = Upload.url({material.file, material})
      assert path =~ "/uploads/test/materials/upload.txt"

      assert {:ok, _} = Course.delete_material(material)
      assert Repo.get(Material, material.id) == nil
      refute File.exists?("uploads/test/materials/upload.txt")
    end

    test "list folder content" do
      folder = insert(:material_folder)
      folder2 = insert(:material_folder, %{parent: folder})
      _ = insert(:material_file, %{parent: folder2})
      _ = insert(:material_file, %{parent: folder2})
      file3 = insert(:material_file, %{parent: folder})

      result = Course.list_material_folders(folder)

      assert Enum.count(result) == 2

      set =
        result
        |> Enum.map(& &1.id)
        |> MapSet.new()

      assert MapSet.member?(set, folder2.id)
      assert MapSet.member?(set, file3.id)
    end

    test "delete a folder" do
      folder = insert(:material_folder)
      folder2 = insert(:material_folder, %{parent: folder})
      file1 = insert(:material_file, %{parent: folder2})
      file2 = insert(:material_file, %{parent: folder2})
      file3 = insert(:material_file, %{parent: folder})

      assert {:ok, _} = Course.delete_material(folder.id)

      [file1, file2, file3, folder, folder2]
      |> Enum.each(&assert(Repo.get(Material, &1.id) == nil))
    end
  end
end
